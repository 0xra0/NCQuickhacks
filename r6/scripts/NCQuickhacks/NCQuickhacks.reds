// =============================================================================
//  NCQuickhacks - Anti-Cyberware & Tech Sabotage
//
//  Design constraint: ZERO @replaceMethod.
//  CharmQuickhack already @replaceMethod's ScriptedPuppetPS.GetAllChoices and
//  QuickHackableHelper.WillHackRevealPlayer in this install. Everything here is
//  @wrapMethod / @addMethod / @addField so nothing collides.
//
//  Lifecycle is driven off NPCPuppet.OnStatusEffectApplied / OnStatusEffectRemoved
//  rather than an Effector, so no TweakDB effector wiring is needed and the
//  engine still guarantees the cleanup callback when the duration expires, the
//  NPC dies, or the effect is cured.
// =============================================================================


// -----------------------------------------------------------------------------
//  Shared helpers
// -----------------------------------------------------------------------------

public class NCQ_Util {

  // Nearby hostile puppets around `center`, excluding `center` itself.
  // Searched from the player because the targeting-system attitude filters are
  // evaluated relative to the searcher.
  public final static func NearbyHostiles(
      player: ref<PlayerPuppet>,
      center: wref<GameObject>,
      radius: Float,
      maxCount: Int32) -> array<wref<ScriptedPuppet>> {

    let out: array<wref<ScriptedPuppet>>;
    let searchQuery: TargetSearchQuery;
    let targetParts: array<TS_TargetPartInfo>;
    let targetingComponent: ref<TargetingComponent>;
    let entity: ref<Entity>;
    let puppet: ref<ScriptedPuppet>;
    let searchDistance: Float;
    let i: Int32 = 0;

    if !IsDefined(player) || !IsDefined(center) {
      return out;
    };

    searchDistance = Vector4.Distance(player.GetWorldPosition(), center.GetWorldPosition()) + radius + 5.0;
    if searchDistance < 20.0 {
      searchDistance = 20.0;
    };
    if searchDistance > 80.0 {
      searchDistance = 80.0;
    };

    searchQuery.testedSet = TargetingSet.Complete;
    searchQuery.searchFilter = TSF_And(
      TSF_All((TSFMV.Obj_Puppet | TSFMV.St_QuickHackable) | TSFMV.St_AliveAndActive),
      TSF_Not(TSFMV.Obj_Player),
      TSF_Not(TSFMV.Att_Friendly)
    );
    searchQuery.maxDistance = searchDistance;
    searchQuery.filterObjectByDistance = true;
    searchQuery.includeSecondaryTargets = false;
    searchQuery.ignoreInstigator = true;

    GameInstance.GetTargetingSystem(player.GetGame()).GetTargetParts(player, searchQuery, targetParts);

    if ArraySize(targetParts) > 40 {
      return out;
    };

    while i < ArraySize(targetParts) {
      if ArraySize(out) >= maxCount {
        return out;
      };

      targetingComponent = TS_TargetPartInfo.GetComponent(targetParts[i]);
      if IsDefined(targetingComponent) {
        entity = targetingComponent.GetEntity();
        if IsDefined(entity) {
          puppet = entity as ScriptedPuppet;
          if IsDefined(puppet)
              && !Equals(puppet.GetEntityID(), center.GetEntityID())
              && ScriptedPuppet.IsActive(puppet)
              && Vector4.Distance(center.GetWorldPosition(), puppet.GetWorldPosition()) <= radius {
            ArrayPush(out, puppet);
          };
        };
      };

      i += 1;
    };

    return out;
  }

  // One-directional attitude edit: `from` starts treating `to` as `attitude`.
  // `to` is left untouched, so the relationship can be made asymmetric.
  public final static func SetAttitude(from: wref<GameObject>, to: wref<GameObject>, attitude: EAIAttitude) -> Void {
    let agentFrom: ref<AttitudeAgent>;
    let agentTo: ref<AttitudeAgent>;

    if !IsDefined(from) || !IsDefined(to) {
      return;
    };

    agentFrom = from.GetAttitudeAgent();
    agentTo = to.GetAttitudeAgent();

    if IsDefined(agentFrom) && IsDefined(agentTo) {
      agentFrom.SetAttitudeTowards(agentTo, attitude);
    };
  }

  public final static func ResolveObject(gi: GameInstance, id: EntityID) -> wref<GameObject> {
    return GameInstance.FindEntityByID(gi, id) as GameObject;
  }
}


// -----------------------------------------------------------------------------
//  Per-NPC restore state
// -----------------------------------------------------------------------------

// Smart-Link Scramble: the single ally the target's homing fire was pushed onto.
@addField(NPCPuppet)
private let ncqScrambleVictim: EntityID;

// Optic Overwrite: squadmates whose attitude toward the target was flipped.
@addField(NPCPuppet)
private let ncqOpticSquad: array<EntityID>;

// Optic Overwrite: the attitude group to restore on expiry.
@addField(NPCPuppet)
private let ncqOpticOriginalGroup: CName;


// -----------------------------------------------------------------------------
//  Status effect lifecycle
// -----------------------------------------------------------------------------

@wrapMethod(NPCPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let effectID: TweakDBID;

  if IsDefined(evt.staticData) {
    effectID = evt.staticData.GetID();

    if effectID == t"BaseStatusEffect.NCQ_SmartLinkScramble" {
      this.NCQ_ScrambleOn();
    } else {
      if effectID == t"BaseStatusEffect.NCQ_OpticOverwrite" {
        this.NCQ_OpticOn();
      };
    };
  };

  return result;
}

@wrapMethod(NPCPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let effectID: TweakDBID;

  if IsDefined(evt.staticData) {
    effectID = evt.staticData.GetID();

    if effectID == t"BaseStatusEffect.NCQ_SmartLinkScramble" {
      this.NCQ_ScrambleOff();
    } else {
      if effectID == t"BaseStatusEffect.NCQ_OpticOverwrite" {
        this.NCQ_OpticOff();
      };
    };
  };

  return result;
}


// -----------------------------------------------------------------------------
//  1. SMART-LINK SCRAMBLE
//
//  The target's smart-targeting chip is fed junk telemetry. Mechanically:
//    - a flat -0.9 Accuracy modifier from the status effect package, so lock-on
//      fire sprays instead of homing (TweakDB side, see NCQuickhacks.yaml)
//    - the nearest ally is marked hostile ONE WAY, so the target re-acquires and
//      shoots them, while the ally stays unaware and does not return fire
//
//  Asymmetry is the whole point - this is confusion, not a firefight. Optic
//  Overwrite is the hack that starts an actual shootout.
// -----------------------------------------------------------------------------

@addMethod(NPCPuppet)
private func NCQ_ScrambleOn() -> Void {
  let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
  let candidates: array<wref<ScriptedPuppet>>;
  let victim: wref<ScriptedPuppet>;

  if !IsDefined(player) {
    return;
  };

  candidates = NCQ_Util.NearbyHostiles(player, this, 25.0, 1);
  if ArraySize(candidates) == 0 {
    // No ally in range. The accuracy collapse from the status effect package
    // still applies, so the hack is not wasted.
    return;
  };

  victim = candidates[0];
  this.ncqScrambleVictim = victim.GetEntityID();

  NCQ_Util.SetAttitude(this, victim, EAIAttitude.AIA_Hostile);
}

@addMethod(NPCPuppet)
private func NCQ_ScrambleOff() -> Void {
  let victim: wref<GameObject>;
  let cleared: EntityID;

  if !EntityID.IsDefined(this.ncqScrambleVictim) {
    return;
  };

  victim = NCQ_Util.ResolveObject(this.GetGame(), this.ncqScrambleVictim);
  if IsDefined(victim) {
    NCQ_Util.SetAttitude(this, victim, EAIAttitude.AIA_Friendly);
  };

  this.ncqScrambleVictim = cleared;
}


// -----------------------------------------------------------------------------
//  2. REFLEX BOOSTER JAMMER
//
//  BaseStatusEffect.NCQ_ReflexJammer is inert - it is a trap, not a debuff.
//  Every NPC time-dilation request (Sandevistan, Kerenzikov, and the dodge
//  dilation that shares the same code path) funnels through
//  AISubActionApplyTimeDilation_Record_Implementation.SetTimeDilation.
//  Wrapping it lets the trap fire at exactly the moment the enemy commits to
//  the reflex boost, and returning false suppresses the dilation itself.
// -----------------------------------------------------------------------------

@wrapMethod(AISubActionApplyTimeDilation_Record_Implementation)
public final static func SetTimeDilation(context: ScriptExecutionContext, record: wref<AISubActionApplyTimeDilation_Record>) -> Bool {
  let owner: ref<GameObject> = ScriptExecutionContext.GetOwner(context);

  if IsDefined(owner) && StatusEffectSystem.ObjectHasStatusEffect(owner, t"BaseStatusEffect.NCQ_ReflexJammer") {
    NCQ_ReflexJammer.Misfire(owner);
    return false;
  };

  return wrappedMethod(context, record);
}

public class NCQ_ReflexJammer {

  public final static func Misfire(target: ref<GameObject>) -> Void {
    let gi: GameInstance = target.GetGame();
    let player: ref<PlayerPuppet> = GetPlayer(gi);
    let instigator: EntityID;
    let maxHealth: Float;
    let burst: Float;

    if IsDefined(player) {
      instigator = player.GetEntityID();
    };

    // Consume the trap first so a single application cannot chain-fire.
    StatusEffectHelper.RemoveStatusEffect(target, t"BaseStatusEffect.NCQ_ReflexJammer");

    // Freeze in place.
    StatusEffectHelper.ApplyStatusEffect(target, t"BaseStatusEffect.Stun", instigator);

    // Armor collapse for 6s.
    StatusEffectHelper.ApplyStatusEffect(target, t"BaseStatusEffect.NCQ_ReflexMisfire", instigator);

    // Shock, for the arc VFX and the DoT.
    StatusEffectHelper.ApplyStatusEffect(target, t"BaseStatusEffect.Electrocuted", instigator);

    // Burst of shock damage - 20% of max health, floored so it stays relevant
    // against low-tier mooks who somehow have reflex chrome.
    maxHealth = GameInstance.GetStatsSystem(gi)
      .GetStatValue(Cast<StatsObjectID>(target.GetEntityID()), gamedataStatType.Health);

    burst = MaxF(150.0, maxHealth * 0.20);

    GameInstance.GetStatPoolsSystem(gi).RequestChangingStatPoolValue(
      Cast<StatsObjectID>(target.GetEntityID()),
      gamedataStatPoolType.Health,
      -burst,
      null,
      false,
      false);
  }
}


// -----------------------------------------------------------------------------
//  3. OPTIC OVERWRITE
//
//  Rewrites the IFF tags the target broadcasts. The attitude group swap is done
//  with SetAttitudeGroupUnsavable so it can never persist into a save file, and
//  the per-agent attitudes are flipped BOTH ways so the squad and the target
//  actually trade fire rather than one side standing there.
//
//  The player is never made a participant, so watching from cover stays viable.
// -----------------------------------------------------------------------------

@addMethod(NPCPuppet)
private func NCQ_OpticOn() -> Void {
  let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
  let squad: array<wref<ScriptedPuppet>>;
  let selfAgent: ref<AttitudeAgent> = this.GetAttitudeAgent();
  let mate: wref<ScriptedPuppet>;
  let i: Int32 = 0;

  if !IsDefined(player) || !IsDefined(selfAgent) {
    return;
  };

  // Spoof the broadcast group. Unsavable => never written to the save.
  this.ncqOpticOriginalGroup = selfAgent.GetAttitudeGroup();
  selfAgent.SetAttitudeGroupUnsavable(n"militech");

  squad = NCQ_Util.NearbyHostiles(player, this, 30.0, 8);

  while i < ArraySize(squad) {
    mate = squad[i];

    NCQ_Util.SetAttitude(mate, this, EAIAttitude.AIA_Hostile);
    NCQ_Util.SetAttitude(this, mate, EAIAttitude.AIA_Hostile);

    ArrayPush(this.ncqOpticSquad, mate.GetEntityID());
    i += 1;
  };
}

@addMethod(NPCPuppet)
private func NCQ_OpticOff() -> Void {
  let selfAgent: ref<AttitudeAgent> = this.GetAttitudeAgent();
  let gi: GameInstance = this.GetGame();
  let mate: wref<GameObject>;
  let i: Int32 = 0;

  if IsDefined(selfAgent) && IsNameValid(this.ncqOpticOriginalGroup) {
    selfAgent.SetAttitudeGroupUnsavable(this.ncqOpticOriginalGroup);
  };

  while i < ArraySize(this.ncqOpticSquad) {
    mate = NCQ_Util.ResolveObject(gi, this.ncqOpticSquad[i]);
    if IsDefined(mate) {
      NCQ_Util.SetAttitude(mate, this, EAIAttitude.AIA_Friendly);
      NCQ_Util.SetAttitude(this, mate, EAIAttitude.AIA_Friendly);
    };
    i += 1;
  };

  ArrayClear(this.ncqOpticSquad);
  this.ncqOpticOriginalGroup = n"";
}
