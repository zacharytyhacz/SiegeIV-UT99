class WildcardsHealth extends TournamentHealth;
//abstract;

event float BotDesireability(Pawn Bot)
{
	local float desire;
	local int HealMax;

	HealMax = Bot.Default.Health;
	if (bSuperHeal) HealMax = Min(HealingAmount,HealMax * 2.0);
	desire = Min(HealingAmount, HealMax - Bot.Health);

	if ( (Bot.Weapon != None) && (Bot.Weapon.AIRating > 0.5) )
		desire *= 1.7;
	if ( Bot.Health < 45 )
		return ( FMin(0.03 * desire, 2.2) );
	else
	{
		if ( desire > 6 )
			desire = FMax(desire,25);
		return ( FMin(0.017 * desire, 2.0) ); 
	}
}

function PlayPickupMessage(Pawn Other)
{
	Other.ReceiveLocalizedMessage( class'PickupMessageHealthPlus', 0, None, None, Self.Class );
}

auto state Pickup
{	
	function Touch( actor Other )
	{
		local int HealMax;
		local Pawn P;
			
		if ( ValidTouch(Other) ) 
		{	
			P = Pawn(Other);	
			HealMax = P.health;
			if (bSuperHeal) HealMax = HealingAmount;
			if (P.Health < HealMax) 
			{
				if (Level.Game.LocalLog != None)
					Level.Game.LocalLog.LogPickup(Self, P);
				if (Level.Game.WorldLog != None)
					Level.Game.WorldLog.LogPickup(Self, P);
				P.Health += HealingAmount;
				if (P.Health > HealMax) P.Health = HealMax;
				PlayPickupMessage(P);
				PlaySound (PickupSound,,2.5);
				Other.MakeNoise(0.2);		
				SetRespawn();
			}
		}
	}
}

defaultproperties
{
}
