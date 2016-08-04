//=============================================================================
// sgBaseCore.
// * Revised by 7DS'Lust
//=============================================================================
class sgBaseCore extends sgBuilding;

var float LastMsgSpam;
var bool bCoreDisabled;
var float RuMultiplier;
var float StoredRU; //Spare RU in core
var float SuddenDeathScale;
var PlayerPawn LocalClient;
var TeamInfo MyTeam;

replication
{
	reliable if ( Role==ROLE_Authority )
		RuMultiplier, StoredRU, bCoreDisabled;
}

event PostBeginPlay()
{
	if ( TeamGamePlus(Level.Game) == None )
	{
		Destroy();
		return;
	}
	MaxEnergy = TeamGamePlus(Level.Game).GoalTeamScore*1000;
	Super.PostBeginPlay();
}

simulated event PostNetBeginPlay()
{
	local PlayerPawn P;
	Super.PostNetBeginPlay();
	if ( Level.NetMode == NM_Client )
	{
		ForEach AllActors (class'PlayerPawn', P)
			if ( ViewPort(P.Player) != none )
			{
				LocalClient = P;
				break;
			}
		if ( LocalClient == none )
			Log("Replication messed up: Core replicated before local pawn");
	}
}

function Destruct( optional pawn instigatedBy)
{
    if ( SiegeGI(Level.Game) != None )
        SiegeGI(Level.Game).CoreDestroyed(Self);
	Spawn(class'sgFlash');
	Spawn(class'shockWave');
	Spawn(class'shockRifleWave');
	Destroy();
}

simulated function TeamInfo GetTeamInfo( byte nTeam)
{
	local TeamInfo T;
	ForEach AllActors (class'TeamInfo', T)
		if ( T.TeamIndex == nTeam )
			return T;
}

simulated function int GetTeamSize()
{
	local sgPRI PRI;
	local int i;

	//Get team size optimally
	if ( MyTeam == none || (MyTeam.TeamIndex != Team) )
		MyTeam = GetTeamInfo( Team);
	if ( MyTeam != none )
		return MyTeam.Size;
	//Count players, non optimal
	ForEach AllActors (class'sgPRI', PRI)
	{
		if ( PRI.Team == Team )
			i++;
	}
	return i;
}

simulated function Timer()
{
	local sgPRI a;
	local float SetRU;
	local float MaxRU;
	local bool bRemoveFromStore;
	local int TeamSize, MaxedOut;

	Super.Timer();
	if ( RuMultiplier <= 0 )
		RuMultiplier = 1;

	UpdateScore();

	if ( bCoreDisabled )
		return;
	
	if ( bDisabledByEMP || (Level.NetMode == NM_Client) && class'sgClient'.default.bHighPerformance )
		Goto NO_INCREASE;

	//Auto-upgrade core if there's a big excedent
	if ( (Grade < 1) && (StoredRU > Default.StoredRU) )
	{
		SetRU = fMin( (1.0-Grade) * UpgradeCost, StoredRU);
		StoredRU -= SetRU;
		Grade += SetRU / UpgradeCost;
	}

	//Do not simulate RU generation on enemy players
	if ( LocalClient == none || LocalClient.PlayerReplicationInfo == none || LocalClient.PlayerReplicationInfo.Team == Team )
	{
		TeamSize = GetTeamSize();
		if ( SiegeGI(Level.Game) != none )
			MaxRU = SiegeGI(Level.Game).MaxRUs[Team];
		else if ( (LocalClient != none) && (sgGameReplicationInfo(LocalClient.GameReplicationInfo) != none) )
			MaxRU = sgGameReplicationInfo(LocalClient.GameReplicationInfo).MaxRUs[Team];
		else
			MaxRU = 9999;
		SetRU = fMax(0.05, (10-float(TeamSize)) * 0.05) + Grade * 0.85;
		SetRU *= RuMultiplier * 0.05;
		if ( (StoredRU < 0) && (SetRU*TeamSize < Abs(StoredRU) ) )
			StoredRU += SetRU*TeamSize;
		else
		{
			if ( StoredRU > SetRU*TeamSize*2 )
				bRemoveFromStore = true;
				
/*			{
				StoredRU -= SetRU*TeamSize*2;
				SetRU *= 3;
			}*/
			ForEach AllActors(class'sgPRI', a)
			{
				if( a.Team == Team )
				{
					if ( a.RU >= MaxRU )
						MaxedOut++;
					else
						a.AddRU( SetRU * (1+2*int(bRemoveFromStore)), true);
				}
			}

			if ( MaxedOut > 0 )
				StoredRU += SetRU * 0.5 * MaxedOut; //Those maxed out give half their RU to core
			if ( bRemoveFromStore )
				StoredRU -= SetRU*2*(TeamSize-MaxedOut); //Those not maxed out have substracted additional RU from store

		}
	}
	NO_INCREASE:

	if (myFX != None)
	{
		myFX.RotationRate.Yaw = Energy*0.25;
		myFX.bHidden = Energy <= 0;
		if ( VSize(myFX.Location - Location) > 50 )
			myFX.SetLocation( Location);
	}
}

simulated function FinishBuilding()
{
    Super.FinishBuilding();

    if ( Team < 0 || Team > 4 )
        Team = 0;

	//Team checks? they all use the same texture, sue me.
   	Texture = SpriteRedTeam;

	if (myFX!=None)
		myFX.RotationRate.Yaw = Energy;
}

simulated function MonsterDamage(int Damage, Pawn instigatedBy)
{
    if ( (Energy-=Damage) <= 0 )
	{
		Energy = 0;
		class'SiegeStatics'.static.AnnounceAll( self, "Game Over! The monsters have killed the BaseCore!");
		Destruct();
	}
}

simulated event TakeDamage(int Damage, Pawn instigatedBy, Vector hitLocation, 
  Vector momentum, name damageType)
{
	local int actualDamage;
	local float tempScore;
	local TournamentPlayer p;

	if ( Role < ROLE_Authority || Level.Game == None || bCoreDisabled || instigatedBy == self )
		return;
	
	actualDamage = Level.Game.ReduceDamage(Damage, DamageType, Self, instigatedBy);

	if ( instigatedBy != None && instigatedBy.bIsPlayer )
		{
			if ( TeamGamePlus(Level.Game) != None && instigatedBy.PlayerReplicationInfo.Team == Team )
				{
					actualDamage *= TeamGamePlus(Level.Game).FriendlyFireScale;
					tempScore = -1 * FMin(Energy, actualDamage);
				}
			else
				tempScore = FMin(Energy, actualDamage);

			tempScore *= (1 + Grade/10);

			if (tempScore < 0 || tempScore > 100000)
				return;
			else
				instigatedBy.PlayerReplicationInfo.Score += tempScore/100;
				
			if (instigatedBy.PlayerReplicationInfo.Score < -1000)
				instigatedBy.PlayerReplicationInfo.Score = 0;

			if ( sgPRI(instigatedBy.PlayerReplicationInfo) != None )
			{
				sgPRI(instigatedBy.PlayerReplicationInfo).AddRU((tempScore/7)*RuRewardScale);
				LeechRU( (tempScore/7)*RuRewardScale );
			}
		}
    else
		if ( sgBuilding(instigatedBy) != None && TeamGamePlus(Level.Game) != None && sgBuilding(instigatedBy).Team == Team )
        	actualDamage *= TeamGamePlus(Level.Game).FriendlyFireScale;


	if ( (Level.TimeSeconds - LastMsgSpam) > 2 )
	{
		if ( actualDamage > 0 && instigatedBy != None && ((instigatedBy.bIsPlayer && 
		instigatedBy.PlayerReplicationInfo.Team != Team) || (sgBuilding(instigatedBy) != None && 
		sgBuilding(instigatedBy).Team != Team)) )
			ForEach AllActors (class'TournamentPlayer', P)
				if ( p.PlayerReplicationInfo.Team == Team )
				{
					if ((Energy-actualDamage)/1000 > 2)
						P.ReceiveLocalizedMessage(class'sgCoreWarnMsg', actualDamage);
					else
						P.ReceiveLocalizedMessage(class'sgCoreDyingMsg', actualDamage);
				}
		LastMsgSpam = Level.TimeSeconds;
	}
	
	Energy -= actualDamage;
	sgPRI(instigatedBy.PlayerReplicationInfo).sgInfoCoreKiller+=actualDamage;

    if (actualDamage>0) Spawn(class'sgFlash');
		if (myFX!=None)
			myFX.RotationRate.Yaw = Energy;

    if ( Energy <= 0 )
		HandleDestruction( instigatedBy);

	UpdateScore();
}

function HandleDestruction( pawn instigatedBy)
{
	local int i, j;
	local sgBaseCore Winner;
	local SiegeGI aGame;
	
	aGame = SiegeGI(Level.Game);
	//Round based game
	if ( (aGame != none) && aGame.bRoundMode )
	{
		bCoreDisabled = True;
		ScaleGlow = 0.1;
		Energy = 0;
		SetCollision(false);
		bProjTarget = False;
		class'SiegeStatics'.static.AnnounceAll( self, "BaseCore destroyed by "$ instigatedBy.PlayerReplicationInfo.PlayerName $"!!");
		For ( i=0 ; i<4 ; i++ )
		{
			if ( (aGame.Cores[i] != none) && !aGame.Cores[i].bCoreDisabled )
			{
				j++;
				Winner = aGame.Cores[i];
			}
		}
		if ( j == 1 )
			aGame.RoundEnded( Winner);
		else //Disable this team from spawning, clear builds
			aGame.DefeatTeam( Team);
		return;
	}
	Energy = 0;
	class'SiegeStatics'.static.AnnounceAll( self, "Game Over! "@instigatedBy.PlayerReplicationInfo.PlayerName@"killed the BaseCore!");
	Destruct( instigatedBy);
}

function UpdateScore()
{
	TeamGamePlus(Level.Game).Teams[Team].Score = (Energy/MaxEnergy)*100;
}

defaultproperties
{
     NetPriority=2.2
	 bNoRemove=True
	 StoredRU=10
     RuMultiplier=1
     bOnlyOwnerRemove=True
     RuRewardScale=1
     BuildingName="Base Core"
     UpgradeCost=80
     MaxEnergy=20000.000000
     SpriteScale=1.000000
     Model=LodMesh'Botpack.Diamond'
     SkinRedTeam=Texture'CoreSkinTeam0'
     SkinBlueTeam=Texture'CoreSkinTeam1'
     SkinGreenTeam=Texture'CoreSkinTeam2'
     SkinYellowTeam=Texture'CoreSkinTeam3'
     SpriteRedTeam=Texture'SKFlare'
     SpriteBlueTeam=Texture'SKFlare'
     SpriteGreenTeam=Texture'SKFlare'
     SpriteYellowTeam=Texture'SKFlare'
     DSofMFX=2.600000
     bAlwaysRelevant=True
     MultiSkins(0)=Texture'SKFlare'
     MultiSkins(1)=Texture'SKFlare'
     MultiSkins(2)=Texture'SKFlare'
     MultiSkins(3)=Texture'SKFlare'
     GUI_Icon=Texture'GUI_Core'
     bCollideWorld=True
     bReplicateEMP=True
     DoneBuilding=True
}
