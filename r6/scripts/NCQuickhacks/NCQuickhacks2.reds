// =============================================================================
//  NCQuickhacks vol.2 - Sensory, Control, Metabolic, Financial
//    4. Phantom Overlay        - false optical contact, squad breaks formation
//    5. Motor Cortex Inversion - spatial awareness scrambled (stat-driven)
//    6. Adrenaline Overdose    - forced berserk + cardiovascular strain
//    7. Crypto-Siphon          - drains eddies, pays out big on the kill
//
//  Same constraints as vol.1: zero @replaceMethod, lifecycle off
//  NPCPuppet.OnStatusEffectApplied / OnStatusEffectRemoved.
// =============================================================================


// -----------------------------------------------------------------------------
//  Repeating tick payloads
// -----------------------------------------------------------------------------

public class NCQ_PhantomTickEvent extends Event {}
public class NCQ_AdrenalineTickEvent extends Event {}
public class NCQ_SiphonTickEvent extends Event {}

@addField(NPCPuppet)
private let ncqPhantomActive: Bool;

@addField(NPCPuppet)
private let ncqAdrenalineActive: Bool;

@addField(NPCPuppet)
private let ncqSiphonActive: Bool;

@addField(NPCPuppet)
private let ncqSiphonTotal: Int32;


// -----------------------------------------------------------------------------
//  Lifecycle
// -----------------------------------------------------------------------------

@wrapMethod(NPCPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let id: TweakDBID;

  if IsDefined(evt.staticData) {
    id = evt.staticData.GetID();

    if id == t"BaseStatusEffect.NCQ_PhantomOverlay" {
      this.NCQ_PhantomOn();
    };
    if id == t"BaseStatusEffect.NCQ_AdrenalineOverdose" {
      this.NCQ_AdrenalineOn();
    };
    if id == t"BaseStatusEffect.NCQ_CryptoSiphon" {
      this.NCQ_SiphonOn();
    };
    if id == t"BaseStatusEffect.NCQ_MotorCortexInversion" {
      this.NCQ_MotorOn();
    };
  };

  return result;
}

@wrapMethod(NPCPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let id: TweakDBID;

  if IsDefined(evt.staticData) {
    id = evt.staticData.GetID();

    if id == t"BaseStatusEffect.NCQ_PhantomOverlay" {
      this.ncqPhantomActive = false;
    };
    if id == t"BaseStatusEffect.NCQ_AdrenalineOverdose" {
      this.NCQ_AdrenalineOff();
    };
    if id == t"BaseStatusEffect.NCQ_CryptoSiphon" {
      this.NCQ_SiphonOff();
    };
    if id == t"BaseStatusEffect.NCQ_MotorCortexInversion" {
      this.NCQ_MotorOff();
    };
  };

  return result;
}


// -----------------------------------------------------------------------------
//  5. MOTOR CORTEX INVERSION
//
//  True input inversion is not reachable: NPCs are driven by behaviour trees and
//  navigation, not by an input axis there is anything to negate. What IS
//  reachable, and reads the same from the outside, is desynchronising them from
//  real time - per-NPC time dilation makes movement sluggish and jerky, which
//  combined with the accuracy and attack-speed collapse from the status effect
//  package looks exactly like a body that has stopped taking orders.
// -----------------------------------------------------------------------------

// NPCPuppet already inherits TimeDilatable, so these call straight through.
@addMethod(NPCPuppet)
private func NCQ_MotorOn() -> Void {
  this.SetIndividualTimeDilation(n"NCQMotorCortex", 0.55);
}

@addMethod(NPCPuppet)
private func NCQ_MotorOff() -> Void {
  this.UnsetIndividualTimeDilation();
}


// -----------------------------------------------------------------------------
//  4. PHANTOM OVERLAY
//
//  A false optical contact is written into the target's feed. There is no
//  spawned decoy entity - instead the squadmate FURTHEST from the player is
//  used as the position anchor, and distraction stimuli are broadcast from it
//  to the target and the rest of the squad on a repeating tick.
//
//  The crowd behaviour is the point: everyone breaks formation and converges on
//  a point that is, by construction, away from you.
// -----------------------------------------------------------------------------

@addMethod(NPCPuppet)
private func NCQ_PhantomOn() -> Void {
  this.ncqPhantomActive = true;
  this.NCQ_PhantomTick();
}

@addMethod(NPCPuppet)
private func NCQ_PhantomTick() -> Void {
  let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
  let squad: array<wref<ScriptedPuppet>>;
  let anchor: wref<ScriptedPuppet>;
  let best: Float = -1.0;
  let d: Float;
  let i: Int32 = 0;

  if !this.ncqPhantomActive || !IsDefined(player) {
    return;
  };

  squad = NCQ_Util.NearbyHostiles(player, this, 35.0, 8);

  // Anchor on whichever body is furthest from the player, so the phantom
  // always pulls attention away rather than onto you.
  while i < ArraySize(squad) {
    d = Vector4.Distance(player.GetWorldPosition(), squad[i].GetWorldPosition());
    if d > best {
      best = d;
      anchor = squad[i];
    };
    i += 1;
  };

  if IsDefined(anchor) {
    StimBroadcasterComponent.SendStimDirectly(anchor, gamedataStimType.SoundDistraction, this);

    i = 0;
    while i < ArraySize(squad) {
      if !Equals(squad[i].GetEntityID(), anchor.GetEntityID()) {
        StimBroadcasterComponent.SendStimDirectly(anchor, gamedataStimType.SoundDistraction, squad[i]);
      };
      i += 1;
    };
  };

  GameInstance.GetDelaySystem(this.GetGame())
    .DelayEvent(this, new NCQ_PhantomTickEvent(), 1.5);
}

@addMethod(NPCPuppet)
protected cb func OnNCQ_PhantomTickEvent(evt: ref<NCQ_PhantomTickEvent>) -> Bool {
  this.NCQ_PhantomTick();
  return true;
}


// -----------------------------------------------------------------------------
//  6. ADRENALINE OVERDOSE
//
//  Forces the injectors wide open. Berserk comes from the vanilla cyberpsychosis
//  package, which already makes an NPC engage everything including its own
//  squad. The cost is metabolic: health bleeds every second, and when the rush
//  ends they are left wide open.
// -----------------------------------------------------------------------------

@addMethod(NPCPuppet)
private func NCQ_AdrenalineOn() -> Void {
  let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
  let instigator: EntityID;

  if IsDefined(player) {
    instigator = player.GetEntityID();
  };

  this.ncqAdrenalineActive = true;

  // Vanilla cyberpsycho package - attacks everything nearby, ignores cover.
  StatusEffectHelper.ApplyStatusEffect(this, t"BaseStatusEffect.MasterOfPuppets", instigator);

  this.NCQ_AdrenalineTick();
}

@addMethod(NPCPuppet)
private func NCQ_AdrenalineTick() -> Void {
  let gi: GameInstance;
  let maxHealth: Float;

  if !this.ncqAdrenalineActive {
    return;
  };

  gi = this.GetGame();

  maxHealth = GameInstance.GetStatsSystem(gi)
    .GetStatValue(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatType.Health);

  // ~3.5% of max health per second. Enough to matter over 15s without simply
  // killing the target outright, which would waste the berserk.
  GameInstance.GetStatPoolsSystem(gi).RequestChangingStatPoolValue(
    Cast<StatsObjectID>(this.GetEntityID()),
    gamedataStatPoolType.Health,
    -(maxHealth * 0.035),
    null,
    false,
    false);

  GameInstance.GetDelaySystem(gi).DelayEvent(this, new NCQ_AdrenalineTickEvent(), 1.0);
}

@addMethod(NPCPuppet)
protected cb func OnNCQ_AdrenalineTickEvent(evt: ref<NCQ_AdrenalineTickEvent>) -> Bool {
  this.NCQ_AdrenalineTick();
  return true;
}

@addMethod(NPCPuppet)
private func NCQ_AdrenalineOff() -> Void {
  let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
  let instigator: EntityID;

  if !this.ncqAdrenalineActive {
    return;
  };

  this.ncqAdrenalineActive = false;

  if IsDefined(player) {
    instigator = player.GetEntityID();
  };

  StatusEffectHelper.RemoveStatusEffect(this, t"BaseStatusEffect.MasterOfPuppets");

  // The crash. Gasping, wide open to a melee finisher.
  if ScriptedPuppet.IsActive(this) {
    StatusEffectHelper.ApplyStatusEffect(this, t"BaseStatusEffect.NCQ_AdrenalineCrash", instigator);
  };
}


// -----------------------------------------------------------------------------
//  7. CRYPTO-SIPHON
//
//  A worm on the target's personal shard. Pays a trickle while they live, and a
//  lump sum if they die still infected - so the incentive is to leave them
//  breathing as long as you can stand to.
// -----------------------------------------------------------------------------

@addMethod(NPCPuppet)
private func NCQ_SiphonOn() -> Void {
  this.ncqSiphonActive = true;
  this.ncqSiphonTotal = 0;
  this.NCQ_SiphonTick();
}

@addMethod(NPCPuppet)
private func NCQ_SiphonTick() -> Void {
  let gi: GameInstance;
  let player: ref<PlayerPuppet>;
  let take: Int32;

  if !this.ncqSiphonActive {
    return;
  };

  gi = this.GetGame();
  player = GetPlayer(gi);

  if IsDefined(player) {
    take = RandRange(12, 30);
    GameInstance.GetTransactionSystem(gi).GiveItem(player, MarketSystem.Money(), take);
    this.ncqSiphonTotal += take;
  };

  GameInstance.GetDelaySystem(gi).DelayEvent(this, new NCQ_SiphonTickEvent(), 1.0);
}

@addMethod(NPCPuppet)
protected cb func OnNCQ_SiphonTickEvent(evt: ref<NCQ_SiphonTickEvent>) -> Bool {
  this.NCQ_SiphonTick();
  return true;
}

@addMethod(NPCPuppet)
private func NCQ_SiphonOff() -> Void {
  let gi: GameInstance;
  let player: ref<PlayerPuppet>;
  let payout: Int32;

  if !this.ncqSiphonActive {
    return;
  };

  this.ncqSiphonActive = false;
  gi = this.GetGame();
  player = GetPlayer(gi);

  // Status effects are stripped on death too, so "no longer active" is how the
  // bankrupt protocol detects the kill without needing a death hook.
  if IsDefined(player) && !ScriptedPuppet.IsActive(this) {
    payout = 1500 + this.ncqSiphonTotal * 4;
    GameInstance.GetTransactionSystem(gi).GiveItem(player, MarketSystem.Money(), payout);
  };

  this.ncqSiphonTotal = 0;
}
