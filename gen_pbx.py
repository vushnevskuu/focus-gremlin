#!/usr/bin/env python3
import uuid
from pathlib import Path


def uid():
    return uuid.uuid4().hex.upper()[:24]


project_id = uid()
app_target_id = uid()
test_target_id = uid()
project_config_list = uid()
app_config_list = uid()
test_config_list = uid()
debug_app = uid()
release_app = uid()
debug_test = uid()
release_test = uid()
debug_proj = uid()
release_proj = uid()
app_product_ref = uid()
test_product_ref = uid()
sources_phase_app = uid()
sources_phase_test = uid()
frameworks_phase_app = uid()
frameworks_phase_test = uid()
resources_phase = uid()
target_dependency = uid()
container_proxy = uid()

groups = {k: uid() for k in [
    "root", "products", "main", "app", "overlay", "ui", "focus", "llm",
    "character", "persistence", "settings", "onboarding", "permissions",
    "utilities", "smart", "tests",
]}

plist_ref = uid()
ent_ref = uid()
assets_ref = uid()
assets_build = uid()

swift_files = [
    ("app", "FocusGremlinApp.swift"),
    ("app", "AppDelegate.swift"),
    ("app", "CompanionSession.swift"),
    ("app", "RootShellView.swift"),
    ("overlay", "OverlayPanelController.swift"),
    ("overlay", "CompanionViewModel.swift"),
    ("ui", "CompanionBubbleView.swift"),
    ("ui", "TypingDotsView.swift"),
    ("focus", "FocusTypes.swift"),
    ("focus", "FocusClassifier.swift"),
    ("focus", "InterruptionPolicy.swift"),
    ("focus", "AppSwitchHysteresis.swift"),
    ("focus", "ScrollSessionTracker.swift"),
    ("focus", "WindowContextProvider.swift"),
    ("focus", "ScrollWheelMonitor.swift"),
    ("focus", "FocusEngineService.swift"),
    ("llm", "LLMProvider.swift"),
    ("llm", "MockLLMProvider.swift"),
    ("llm", "MLXProvider.swift"),
    ("llm", "OllamaProvider.swift"),
    ("llm", "GremlinPrompts.swift"),
    ("llm", "GremlinContextBuilder.swift"),
    ("llm", "GremlinOrchestrator.swift"),
    ("character", "GremlinCompanionSpriteStateMachine.swift"),
    ("character", "RecentMessageMemory.swift"),
    ("character", "TemplatePhraseBank.swift"),
    ("character", "MessageSelector.swift"),
    ("persistence", "SettingsStore.swift"),
    ("settings", "SettingsRootView.swift"),
    ("onboarding", "OnboardingView.swift"),
    ("permissions", "PermissionGate.swift"),
    ("utilities", "AppLogger.swift"),
    ("utilities", "FeatureFlags.swift"),
    ("utilities", "GremlinSpriteSheetGeometry.swift"),
    ("utilities", "LoginItemManager.swift"),
    ("utilities", "GremlinTypingVoicePlayer.swift"),
    ("smart", "SmartCategoryMerge.swift"),
    ("smart", "ScreenCaptureService.swift"),
    ("smart", "OllamaVisionClassifier.swift"),
    ("smart", "SmartModeController.swift"),
]

file_refs = {}
build_files = {}
for folder, name in swift_files:
    key = f"{folder}/{name}"
    file_refs[key] = uid()
    build_files[key] = uid()

test_file = "FocusGremlinTests.swift"
test_ref = uid()
test_build = uid()

lines: list[str] = []


def p(s: str = ""):
    lines.append(s)


p("// !$*UTF8*$!")
p("{")
p("\tarchiveVersion = 1;")
p("\tclasses = {};")
p("\tobjectVersion = 56;")
p("\tobjects = {")

p("\n/* Begin PBXBuildFile section */")
for folder, name in swift_files:
    key = f"{folder}/{name}"
    p(
        f"\t\t{build_files[key]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[key]} /* {name} */; }};"
    )
p(f"\t\t{test_build} /* {test_file} in Sources */ = {{isa = PBXBuildFile; fileRef = {test_ref} /* {test_file} */; }};")
p(
    f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};"
)
p("/* End PBXBuildFile section */")

p("\n/* Begin PBXFileReference section */")
p(
    f"\t\t{app_product_ref} /* FocusGremlin.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FocusGremlin.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
p(
    f"\t\t{test_product_ref} /* FocusGremlinTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = FocusGremlinTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
p(
    f"\t\t{plist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
)
p(
    f"\t\t{ent_ref} /* FocusGremlin.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = FocusGremlin.entitlements; sourceTree = \"<group>\"; }};"
)
p(
    f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};"
)
for folder, name in swift_files:
    key = f"{folder}/{name}"
    p(
        f"\t\t{file_refs[key]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
    )
p(
    f"\t\t{test_ref} /* {test_file} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {test_file}; sourceTree = \"<group>\"; }};"
)
p("/* End PBXFileReference section */")

p("\n/* Begin PBXFrameworksBuildPhase section */")
p(f"\t\t{frameworks_phase_app} /* Frameworks */ = {{")
p("\t\t\tisa = PBXFrameworksBuildPhase;")
p("\t\t\tbuildActionMask = 2147483647;")
p("\t\t\tfiles = (")
p("\t\t\t);")
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
p("\t\t};")
p(f"\t\t{frameworks_phase_test} /* Frameworks */ = {{")
p("\t\t\tisa = PBXFrameworksBuildPhase;")
p("\t\t\tbuildActionMask = 2147483647;")
p("\t\t\tfiles = (")
p("\t\t\t);")
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
p("\t\t};")
p("/* End PBXFrameworksBuildPhase section */")

p("\n/* Begin PBXGroup section */")
p(f"\t\t{groups['root']} = {{")
p("\t\t\tisa = PBXGroup;")
p("\t\t\tchildren = (")
p(f"\t\t\t\t{groups['main']} /* FocusGremlin */,")
p(f"\t\t\t\t{groups['products']} /* Products */,")
p(f"\t\t\t\t{groups['tests']} /* FocusGremlinTests */,")
p("\t\t\t);")
p("\t\t\tsourceTree = \"<group>\";")
p("\t\t};")

p(f"\t\t{groups['products']} = {{")
p("\t\t\tisa = PBXGroup;")
p("\t\t\tchildren = (")
p(f"\t\t\t\t{app_product_ref} /* FocusGremlin.app */,")
p(f"\t\t\t\t{test_product_ref} /* FocusGremlinTests.xctest */,")
p("\t\t\t);")
p("\t\t\tname = Products;")
p("\t\t\tsourceTree = \"<group>\";")
p("\t\t};")


def subgroup(path_name: str, key: str, child_keys: list[str]):
    p(f"\t\t{groups[key]} = {{")
    p("\t\t\tisa = PBXGroup;")
    p("\t\t\tchildren = (")
    for ck in child_keys:
        p(f"\t\t\t\t{ck},")
    p("\t\t\t);")
    p(f"\t\t\tpath = {path_name};")
    p("\t\t\tsourceTree = \"<group>\";")
    p("\t\t};")


subgroup(
    "App",
    "app",
    [
        file_refs["app/FocusGremlinApp.swift"],
        file_refs["app/AppDelegate.swift"],
        file_refs["app/CompanionSession.swift"],
        file_refs["app/RootShellView.swift"],
    ],
)
subgroup(
    "Overlay",
    "overlay",
    [
        file_refs["overlay/OverlayPanelController.swift"],
        file_refs["overlay/CompanionViewModel.swift"],
    ],
)
subgroup(
    "UI",
    "ui",
    [file_refs["ui/CompanionBubbleView.swift"], file_refs["ui/TypingDotsView.swift"]],
)
subgroup(
    "FocusEngine",
    "focus",
    [file_refs[f"focus/{n}"] for f, n in swift_files if f == "focus"],
)
subgroup(
    "LLM",
    "llm",
    [file_refs[f"llm/{n}"] for f, n in swift_files if f == "llm"],
)
subgroup(
    "Character",
    "character",
    [file_refs[f"character/{n}"] for f, n in swift_files if f == "character"],
)
subgroup("Persistence", "persistence", [file_refs["persistence/SettingsStore.swift"]])
subgroup("Settings", "settings", [file_refs["settings/SettingsRootView.swift"]])
subgroup("Onboarding", "onboarding", [file_refs["onboarding/OnboardingView.swift"]])
subgroup("Permissions", "permissions", [file_refs["permissions/PermissionGate.swift"]])
subgroup(
    "Utilities",
    "utilities",
    [
        file_refs["utilities/AppLogger.swift"],
        file_refs["utilities/FeatureFlags.swift"],
        file_refs["utilities/LoginItemManager.swift"],
    ],
)
subgroup(
    "SmartMode",
    "smart",
    [
        file_refs["smart/SmartCategoryMerge.swift"],
        file_refs["smart/ScreenCaptureService.swift"],
        file_refs["smart/OllamaVisionClassifier.swift"],
        file_refs["smart/SmartModeController.swift"],
    ],
)

p(f"\t\t{groups['tests']} = {{")
p("\t\t\tisa = PBXGroup;")
p("\t\t\tchildren = (")
p(f"\t\t\t\t{test_ref} /* {test_file} */,")
p("\t\t\t);")
p("\t\t\tpath = FocusGremlinTests;")
p("\t\t\tsourceTree = \"<group>\";")
p("\t\t};")

p(f"\t\t{groups['main']} = {{")
p("\t\t\tisa = PBXGroup;")
p("\t\t\tchildren = (")
p(f"\t\t\t\t{assets_ref} /* Assets.xcassets */,")
p(f"\t\t\t\t{plist_ref} /* Info.plist */,")
p(f"\t\t\t\t{ent_ref} /* FocusGremlin.entitlements */,")
for g in [
    "app",
    "overlay",
    "ui",
    "focus",
    "llm",
    "character",
    "persistence",
    "settings",
    "onboarding",
    "permissions",
    "utilities",
    "smart",
]:
    p(f"\t\t\t\t{groups[g]} /* {g} */,")
p("\t\t\t);")
p("\t\t\tpath = FocusGremlin;")
p("\t\t\tsourceTree = \"<group>\";")
p("\t\t};")

p("/* End PBXGroup section */")

p("\n/* Begin PBXNativeTarget section */")
p(f"\t\t{app_target_id} /* FocusGremlin */ = {{")
p("\t\t\tisa = PBXNativeTarget;")
p(
    f"\t\t\tbuildConfigurationList = {app_config_list} /* Build configuration list for PBXNativeTarget \"FocusGremlin\" */;"
)
p("\t\t\tbuildPhases = (")
p(f"\t\t\t\t{sources_phase_app} /* Sources */,")
p(f"\t\t\t\t{frameworks_phase_app} /* Frameworks */,")
p(f"\t\t\t\t{resources_phase} /* Resources */,")
p("\t\t\t);")
p("\t\t\tbuildRules = ();")
p("\t\t\tdependencies = ();")
p("\t\t\tname = FocusGremlin;")
p("\t\t\tproductName = FocusGremlin;")
p(f"\t\t\tproductReference = {app_product_ref} /* FocusGremlin.app */;")
p("\t\t\tproductType = \"com.apple.product-type.application\";")
p("\t\t};")

p(f"\t\t{test_target_id} /* FocusGremlinTests */ = {{")
p("\t\t\tisa = PBXNativeTarget;")
p(
    f"\t\t\tbuildConfigurationList = {test_config_list} /* Build configuration list for PBXNativeTarget \"FocusGremlinTests\" */;"
)
p("\t\t\tbuildPhases = (")
p(f"\t\t\t\t{sources_phase_test} /* Sources */,")
p(f"\t\t\t\t{frameworks_phase_test} /* Frameworks */,")
p("\t\t\t);")
p("\t\t\tbuildRules = ();")
p("\t\t\tdependencies = (")
p(f"\t\t\t\t{target_dependency} /* PBXTargetDependency */,")
p("\t\t\t);")
p("\t\t\tname = FocusGremlinTests;")
p("\t\t\tproductName = FocusGremlinTests;")
p(f"\t\t\tproductReference = {test_product_ref} /* FocusGremlinTests.xctest */;")
p("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
p("\t\t};")
p("/* End PBXNativeTarget section */")

p("\n/* Begin PBXProject section */")
p(f"\t\t{project_id} /* Project object */ = {{")
p("\t\t\tisa = PBXProject;")
p(
    "\t\t\tattributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500; TargetAttributes = { "
    + f"{app_target_id} = {{ CreatedOnToolsVersion = 15.0; }}; {test_target_id} = {{ CreatedOnToolsVersion = 15.0; TestTargetID = {app_target_id}; }}; "
    + "}; };"
)
p(
    f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"FocusGremlin\" */;"
)
p("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
p("\t\t\tdevelopmentRegion = en;")
p("\t\t\thasScannedForEncodings = 0;")
p("\t\t\tknownRegions = (")
p("\t\t\t\ten,")
p("\t\t\t\tBase,")
p("\t\t\t);")
p(f"\t\t\tmainGroup = {groups['root']};")
p(f"\t\t\tproductRefGroup = {groups['products']} /* Products */;")
p("\t\t\tprojectDirPath = \"\";")
p("\t\t\tprojectRoot = \"\";")
p("\t\t\ttargets = (")
p(f"\t\t\t\t{app_target_id} /* FocusGremlin */,")
p(f"\t\t\t\t{test_target_id} /* FocusGremlinTests */,")
p("\t\t\t);")
p("\t\t};")
p("/* End PBXProject section */")

p("\n/* Begin PBXResourcesBuildPhase section */")
p(f"\t\t{resources_phase} /* Resources */ = {{")
p("\t\t\tisa = PBXResourcesBuildPhase;")
p("\t\t\tbuildActionMask = 2147483647;")
p("\t\t\tfiles = (")
p(f"\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,")
p("\t\t\t);")
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
p("\t\t};")
p("/* End PBXResourcesBuildPhase section */")

p("\n/* Begin PBXSourcesBuildPhase section */")
p(f"\t\t{sources_phase_app} /* Sources */ = {{")
p("\t\t\tisa = PBXSourcesBuildPhase;")
p("\t\t\tbuildActionMask = 2147483647;")
p("\t\t\tfiles = (")
for folder, name in swift_files:
    key = f"{folder}/{name}"
    p(f"\t\t\t\t{build_files[key]} /* {name} in Sources */,")
p("\t\t\t);")
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
p("\t\t};")

p(f"\t\t{sources_phase_test} /* Sources */ = {{")
p("\t\t\tisa = PBXSourcesBuildPhase;")
p("\t\t\tbuildActionMask = 2147483647;")
p("\t\t\tfiles = (")
p(f"\t\t\t\t{test_build} /* {test_file} in Sources */,")
p("\t\t\t);")
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
p("\t\t};")
p("/* End PBXSourcesBuildPhase section */")

p("\n/* Begin PBXContainerItemProxy section */")
p(f"\t\t{container_proxy} /* PBXContainerItemProxy */ = {{")
p("\t\t\tisa = PBXContainerItemProxy;")
p("\t\t\tcontainerPortal = " + project_id + " /* Project object */;")
p("\t\t\tproxyType = 1;")
p(f"\t\t\tremoteGlobalIDString = {app_target_id};")
p("\t\t\tremoteInfo = FocusGremlin;")
p("\t\t};")
p("/* End PBXContainerItemProxy section */")

p("\n/* Begin PBXTargetDependency section */")
p(f"\t\t{target_dependency} /* PBXTargetDependency */ = {{")
p("\t\t\tisa = PBXTargetDependency;")
p(f"\t\t\ttarget = {app_target_id} /* FocusGremlin */;")
p(f"\t\t\ttargetProxy = {container_proxy} /* PBXContainerItemProxy */;")
p("\t\t};")
p("/* End PBXTargetDependency section */")

common_app_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_ENTITLEMENTS": "FocusGremlin/FocusGremlin.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "FocusGremlin/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Focus Gremlin",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.focusgremlin.app",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
}

common_test_settings = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.focusgremlin.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/FocusGremlin.app/Contents/MacOS/FocusGremlin",
}


p("\n/* Begin XCBuildConfiguration section */")
for cfg_id, name, is_debug in [
    (debug_app, "Debug", True),
    (release_app, "Release", False),
]:
    p(f"\t\t{cfg_id} /* {name} */ = {{")
    p("\t\t\tisa = XCBuildConfiguration;")
    p(f"\t\t\tbuildSettings = {{")
    for k, v in common_app_settings.items():
        p(f"\t\t\t\t{k} = {v};")
    p("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    if is_debug:
        p("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
        p("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    else:
        p("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    p("\t\t\t};")
    p(f"\t\t\tname = {name};")
    p("\t\t};")

for cfg_id, name, is_debug in [
    (debug_test, "Debug", True),
    (release_test, "Release", False),
]:
    p(f"\t\t{cfg_id} /* {name} */ = {{")
    p("\t\t\tisa = XCBuildConfiguration;")
    p(f"\t\t\tbuildSettings = {{")
    for k, v in common_test_settings.items():
        p(f"\t\t\t\t{k} = {v};")
    if is_debug:
        p("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    p("\t\t\t};")
    p(f"\t\t\tname = {name};")
    p("\t\t};")

for cfg_id, name, is_debug in [
    (debug_proj, "Debug", True),
    (release_proj, "Release", False),
]:
    p(f"\t\t{cfg_id} /* {name} */ = {{")
    p("\t\t\tisa = XCBuildConfiguration;")
    p("\t\t\tbuildSettings = {")
    p("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    p("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    p("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    p("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    p("\t\t\t\tONLY_ACTIVE_ARCH = YES;" if is_debug else "\t\t\t\tONLY_ACTIVE_ARCH = NO;")
    p("\t\t\t\tSDKROOT = macosx;")
    p("\t\t\t\tSWIFT_VERSION = 5.0;")
    p("\t\t\t};")
    p(f"\t\t\tname = {name};")
    p("\t\t};")

p("/* End XCBuildConfiguration section */")

p("\n/* Begin XCConfigurationList section */")
p(f"\t\t{app_config_list} /* Build configuration list for PBXNativeTarget FocusGremlin */ = {{")
p("\t\t\tisa = XCConfigurationList;")
p("\t\t\tbuildConfigurations = (")
p(f"\t\t\t\t{debug_app} /* Debug */,")
p(f"\t\t\t\t{release_app} /* Release */,")
p("\t\t\t);")
p("\t\t\tdefaultConfigurationIsVisible = 0;")
p("\t\t\tdefaultConfigurationName = Release;")
p("\t\t};")

p(f"\t\t{test_config_list} /* Build configuration list for PBXNativeTarget FocusGremlinTests */ = {{")
p("\t\t\tisa = XCConfigurationList;")
p("\t\t\tbuildConfigurations = (")
p(f"\t\t\t\t{debug_test} /* Debug */,")
p(f"\t\t\t\t{release_test} /* Release */,")
p("\t\t\t);")
p("\t\t\tdefaultConfigurationIsVisible = 0;")
p("\t\t\tdefaultConfigurationName = Release;")
p("\t\t};")

p(f"\t\t{project_config_list} /* Build configuration list for PBXProject FocusGremlin */ = {{")
p("\t\t\tisa = XCConfigurationList;")
p("\t\t\tbuildConfigurations = (")
p(f"\t\t\t\t{debug_proj} /* Debug */,")
p(f"\t\t\t\t{release_proj} /* Release */,")
p("\t\t\t);")
p("\t\t\tdefaultConfigurationIsVisible = 0;")
p("\t\t\tdefaultConfigurationName = Release;")
p("\t\t};")
p("/* End XCConfigurationList section */")

p("\t};")
p(f"\trootObject = {project_id} /* Project object */;")
p("}")

out_path = Path(__file__).resolve().parent / "FocusGremlin.xcodeproj" / "project.pbxproj"
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Wrote {out_path}")
