use libboss_core::*;

#[test]
fn catalog_entries_expose_family_and_category() {
    let product = product_for_id(0x4082).expect("known product");
    assert_eq!(product.family, BossProductFamily::QCUltra2);
    assert_eq!(product.category, BossProductCategory::Headphones);
}

#[test]
fn capability_resolution_uses_function_blocks_and_product_family() {
    let product = product_for_id(0x4082).expect("known product");
    let protocol_support = BossProtocolSupport {
        function_blocks: FunctionBlockSet::from_bytes(&[0x80, 0x00, 0x00, 0x02]),
        transport_kind: BossTransportKind::Ble,
        default_device_id: 0,
        default_port: 0,
    };

    let capabilities = BossDeviceCapabilities::resolve(Some(product), &protocol_support);

    assert_eq!(capabilities.settings.standby_timer, BossFeatureAccess::ReadWrite);
    assert_eq!(capabilities.audio_modes.modes, BossFeatureSupport::Supported);
    assert_eq!(capabilities.sound.equalizer, BossFeatureAccess::ReadWrite);
}

#[test]
fn capability_resolution_marks_missing_blocks_unsupported() {
    let protocol_support = BossProtocolSupport {
        function_blocks: FunctionBlockSet::from_bytes(&[]),
        transport_kind: BossTransportKind::Ble,
        default_device_id: 0,
        default_port: 0,
    };

    let capabilities = BossDeviceCapabilities::resolve(None, &protocol_support);

    assert_eq!(capabilities.settings.standby_timer, BossFeatureAccess::Unsupported);
    assert_eq!(capabilities.audio_modes.modes, BossFeatureSupport::Unsupported);
    assert_eq!(capabilities.sound.equalizer, BossFeatureAccess::Unsupported);
}

#[test]
fn qc_ultra_2_catalog_implies_settings_and_audio_modes_blocks() {
    let product = product_for_id(0x4082).expect("known product");
    let implied = implied_function_blocks_for_product(Some(product)).expect("fallback blocks");

    assert!(implied.contains(BmapFunctionBlock::Settings));
    assert!(implied.contains(BmapFunctionBlock::AudioModes));
}
