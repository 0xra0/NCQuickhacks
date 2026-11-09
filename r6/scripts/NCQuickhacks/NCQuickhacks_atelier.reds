// =============================================================================
//  NCQuickhacks - Virtual Atelier storefront
//
//  OPTIONAL FILE. This is the only part of the mod that depends on another
//  mod: it references VirtualShopRegistration, so if Virtual Atelier is not
//  installed the type is unresolved and redscript refuses to compile the whole
//  r6/scripts tree - which takes every other script mod down with it.
//  install.sh checks for the type and skips copying this file if it is absent.
//
//  Everything else (the 7 hacks, the netrunner vendor stock in
//  NCQuickhacks_vendors.yaml) works with this file deleted.
// =============================================================================

@addMethod(gameuiInGameMenuGameController)
protected cb func RegisterNCQuickhacksStore(event: ref<VirtualShopRegistration>) -> Bool {
  // Order is load-bearing: items[] and prices[] are matched by index.
  // Prices track RAM cost - the cheap utility hacks are the cheap purchases.
  event.AddStore(
    n"NCQ_QUICKHACKS",
    "Night City Quickhacks",
    [
      "Items.NCQ_CryptoSiphonProgram",           //  6 RAM
      "Items.NCQ_SmartLinkScrambleProgram",      //  8 RAM
      "Items.NCQ_MotorCortexInversionProgram",   //  9 RAM
      "Items.NCQ_PhantomOverlayProgram",         // 10 RAM
      "Items.NCQ_ReflexJammerProgram",           // 10 RAM
      "Items.NCQ_OpticOverwriteProgram",         // 12 RAM
      "Items.NCQ_AdrenalineOverdoseProgram"      // 14 RAM
    ],
    [ 4000, 7000, 8000, 10000, 11000, 15000, 18000 ],
    r"base/ncquickhacks/ui/ncq_store.inkatlas",
    n"NCQStore",
    // A single-element qualities array is VA's "apply to all" form -
    // GetStoreQualities promotes qualities[0] to the default for every item.
    [ "Legendary" ]
  );
}
