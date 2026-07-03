#!/usr/bin/env python3
"""
Generates the Xcode project file for TableTogetherTV (tvOS target).
Includes shared models from the main TableTogether app and tvOS-specific views.
"""
import os
import uuid

# Generate a deterministic UUID based on the file path
def generate_uuid(path):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, path)).upper().replace('-', '')[:24]

# Get all tvOS Swift files
# Project is at TableTogetherTV/TableTogetherTV.xcodeproj
# All file references must be relative to TableTogetherTV/
project_dir = "TableTogetherTV"

tvos_files = []
tvos_base = "TableTogetherTV/Sources"
for root, dirs, files in os.walk(tvos_base):
    for file in files:
        if file.endswith('.swift'):
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, project_dir)
            tvos_files.append(rel_path)

# Get shared model files from main TableTogether app
shared_dirs = [
    "TableTogether/Sources/Models",
    "TableTogether/Sources/Extensions",
    "TableTogether/Sources/CoreData"
]

# Individual shared service files needed by tvOS
shared_service_files = [
    "TableTogether/Sources/Services/AppLogger.swift",
    "TableTogether/Sources/Services/PendingInvitationStore.swift",
    "TableTogether/Sources/Services/RecipeIngredientResolver.swift",
    "TableTogether/Sources/Services/UserIdentity.swift",
    "TableTogether/Sources/Views/Shared/Theme.swift",
    "TableTogether/Sources/Views/Shared/RecipeImageLoader.swift",
    "TableTogether/Sources/Views/AppTypography.swift"
]

# Core Data model resource (included separately as a resource, not a source file)
core_data_model = "TableTogether/Sources/CoreData/TableTogether.xcdatamodeld"

shared_files = []
for shared_dir in shared_dirs:
    if os.path.exists(shared_dir):
        for root, dirs, files in os.walk(shared_dir):
            for file in files:
                if file.endswith('.swift'):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, project_dir)
                    shared_files.append(rel_path)

# Add individual shared service files
for service_file in shared_service_files:
    if os.path.exists(service_file):
        shared_files.append(os.path.relpath(service_file, project_dir))

# Combine all files
all_files = sorted(tvos_files + shared_files)

# Generate file references
file_refs = []
build_files = []
children_refs = []
source_files = []

for f in all_files:
    file_id = generate_uuid(f + "_tv")
    build_id = generate_uuid(f + "_tv_build")
    name = os.path.basename(f)

    file_refs.append(f'\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{f}"; sourceTree = "<group>"; }};')
    build_files.append(f'\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};')
    children_refs.append(f'\t\t\t\t{file_id} /* {name} */,')
    source_files.append(f'\t\t\t\t{build_id} /* {name} in Sources */,')

# Add Core Data model (.xcdatamodeld) as a source file
xcdatamodeld_file_id = generate_uuid(core_data_model + "_tv")
xcdatamodeld_build_id = generate_uuid(core_data_model + "_tv_build")
xcdatamodeld_name = os.path.basename(core_data_model)

core_data_model_rel = os.path.relpath(core_data_model, project_dir)
file_refs.append(f'\t\t{xcdatamodeld_file_id} /* {xcdatamodeld_name} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; path = "{core_data_model_rel}"; sourceTree = "<group>"; }};')
build_files.append(f'\t\t{xcdatamodeld_build_id} /* {xcdatamodeld_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {xcdatamodeld_file_id} /* {xcdatamodeld_name} */; }};')
children_refs.append(f'\t\t\t\t{xcdatamodeld_file_id} /* {xcdatamodeld_name} */,')
source_files.append(f'\t\t\t\t{xcdatamodeld_build_id} /* {xcdatamodeld_name} in Sources */,')

# Join with newlines
file_refs_str = '\n'.join(file_refs)
build_files_str = '\n'.join(build_files)
children_refs_str = '\n'.join(children_refs)
source_files_str = '\n'.join(source_files)

# Create project content
project_content = f'''// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_files_str}
\t\tE47DE5E9F0C6D4C911200011 /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = E47DE5E9F0C6D4C911200012 /* Assets.xcassets */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t089C1665FEEF756F011CA5E2 /* Foundation.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Foundation.framework; path = System/Library/Frameworks/Foundation.framework; sourceTree = SDKROOT; }};
\t\tE47DE5E9F0C6D4C911200012 /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Assets.xcassets"; sourceTree = SOURCE_ROOT; }};
{file_refs_str}
\t\tE47DE5E9F0C6D4C911100002 /* TableTogetherTV.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TableTogetherTV.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\tE47DE5E9F0C6D4C911200010 /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t089C1665FEEF756F011CA5E3 /* TableTogetherTV */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children_refs_str}
\t\t\t);
\t\t\tpath = .;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t19C28FACFE9D520D11CA2CBB /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tE47DE5E9F0C6D4C911100002 /* TableTogetherTV.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXResourcesBuildPhase section */
\t\tE47DE5E9F0C6D4C911200013 /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\tE47DE5E9F0C6D4C911200011 /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXNativeTarget section */
\t\tE47DE5E9F0C6D4C911000002 /* TableTogetherTV */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = E47DE5E9F0C6D4C911400002 /* Build configuration list for PBXNativeTarget "TableTogetherTV" */;
\t\t\tbuildPhases = (
\t\t\t\tE47DE5E9F0C6D4C911300002 /* Sources */,
\t\t\t\tE47DE5E9F0C6D4C911200010 /* Frameworks */,
\t\t\t\tE47DE5E9F0C6D4C911200013 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = TableTogetherTV;
\t\t\tproductName = TableTogetherTV;
\t\t\tproductReference = E47DE5E9F0C6D4C911100002 /* TableTogetherTV.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t089C1665FEEF756F011CA5E0 /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = YES;
\t\t\t\tLastSwiftUpdateCheck = 1520;
\t\t\t\tLastUpgradeCheck = 1520;
\t\t\t}};
\t\t\tbuildConfigurationList = E47DE5E9F0C6D4C911500002 /* Build configuration list for PBXProject "TableTogetherTV" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = 089C1665FEEF756F011CA5E3 /* TableTogetherTV */;
\t\t\tproductRefGroup = 19C28FACFE9D520D11CA2CBB /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\tE47DE5E9F0C6D4C911000002 /* TableTogetherTV */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
\t\tE47DE5E9F0C6D4C911300002 /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{source_files_str}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\tE47DE5E9F0C6D4C911600003 /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;
\t\t\t\tASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR = default;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = TableTogetherTV.entitlements;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tVERSIONING_SYSTEM = "apple-generic";
\t\t\t\tDEVELOPMENT_TEAM = N6BK2WX94Z;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tTVOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMARKETING_VERSION = 1.4;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = TableTogetherTV/Info.plist;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIUserInterfaceStyle = Dark;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = dev.dreamfold.tabletogether.tv;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = appletvos;
\t\t\t\tSUPPORTED_PLATFORMS = "appletvos appletvsimulator";
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.2;
\t\t\t\tTARGETED_DEVICE_FAMILY = 3;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\tE47DE5E9F0C6D4C911600004 /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;
\t\t\t\tASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR = default;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = TableTogetherTV.entitlements;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tVERSIONING_SYSTEM = "apple-generic";
\t\t\t\tDEVELOPMENT_TEAM = N6BK2WX94Z;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tTVOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMARKETING_VERSION = 1.4;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = TableTogetherTV/Info.plist;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIUserInterfaceStyle = Dark;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = dev.dreamfold.tabletogether.tv;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = appletvos;
\t\t\t\tSUPPORTED_PLATFORMS = "appletvos appletvsimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.2;
\t\t\t\tTARGETED_DEVICE_FAMILY = 3;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\tE47DE5E9F0C6D4C911700003 /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tVERSIONING_SYSTEM = "apple-generic";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\tE47DE5E9F0C6D4C911700004 /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tVERSIONING_SYSTEM = "apple-generic";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\tE47DE5E9F0C6D4C911400002 /* Build configuration list for PBXNativeTarget "TableTogetherTV" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tE47DE5E9F0C6D4C911600003 /* Debug */,
\t\t\t\tE47DE5E9F0C6D4C911600004 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\tE47DE5E9F0C6D4C911500002 /* Build configuration list for PBXProject "TableTogetherTV" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tE47DE5E9F0C6D4C911700003 /* Debug */,
\t\t\t\tE47DE5E9F0C6D4C911700004 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = 089C1665FEEF756F011CA5E0 /* Project object */;
}}
'''

# Write the project file
os.makedirs('TableTogetherTV/TableTogetherTV.xcodeproj', exist_ok=True)
with open('TableTogetherTV/TableTogetherTV.xcodeproj/project.pbxproj', 'w') as f:
    f.write(project_content)

print(f"Generated TableTogetherTV Xcode project with {len(all_files)} Swift files")
print(f"  - tvOS files: {len(tvos_files)}")
print(f"  - Shared files: {len(shared_files)}")
