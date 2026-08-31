#!/usr/bin/env python3
"""
Regenerates DeadlineFloat.xcodeproj from the on-disk source tree.

The project file is fully derived from the file system, so adding or removing a
source file only requires re-running this script:

    python3 Tools/generate_project.py

Object identifiers are md5-derived from stable keys, so regenerating produces a
byte-identical project file when the tree has not changed.
"""

from __future__ import annotations

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

APP_NAME = "DeadlineFloat"
TEST_NAME = "DeadlineFloatTests"
BUNDLE_ID = "com.niravsurabhi.DeadlineFloat"
DEVELOPMENT_TEAM = os.environ.get("DEADLINEFLOAT_TEAM", "GK2Z5G7FG9")
DEPLOYMENT_TARGET = "14.0"
SWIFT_VERSION = "6.0"
MARKETING_VERSION = "1.0"
BUILD_VERSION = "1"

# Directories that hold compiled sources / resources, relative to ROOT.
SOURCE_ROOTS = [APP_NAME, TEST_NAME]

SKIP_DIRS = {".git", ".build", "DerivedData", "__pycache__", ".xcodeproj"}
SKIP_FILES = {".DS_Store"}


def oid(key: str) -> str:
    """Deterministic 24 hex character object identifier."""
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def file_type(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    return {
        ".swift": "sourcecode.swift",
        ".m": "sourcecode.c.objc",
        ".h": "sourcecode.c.h",
        ".plist": "text.plist.xml",
        ".entitlements": "text.plist.entitlements",
        ".xcassets": "folder.assetcatalog",
        ".json": "text.json",
        ".md": "net.daringfireball.markdown",
        ".png": "image.png",
        ".icns": "image.icns",
        ".xcconfig": "text.xcconfig",
    }.get(ext, "text")


def build_phase_for(path: str) -> str | None:
    """Which build phase a file belongs to, or None when it is not built."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".swift":
        return "Sources"
    if ext in (".xcassets", ".png", ".icns", ".json"):
        return "Resources"
    return None


class Node:
    """A directory in the generated group tree."""

    def __init__(self, name: str, rel: str):
        self.name = name
        self.rel = rel
        self.children: list["Node"] = []
        self.files: list[str] = []  # paths relative to ROOT


def scan(rel: str) -> Node:
    node = Node(os.path.basename(rel) or rel, rel)
    abs_dir = os.path.join(ROOT, rel)
    for entry in sorted(os.listdir(abs_dir)):
        if entry in SKIP_FILES or entry in SKIP_DIRS:
            continue
        abs_path = os.path.join(abs_dir, entry)
        rel_path = os.path.join(rel, entry)
        if os.path.isdir(abs_path):
            # Asset catalogs and other bundles are leaf file references.
            if entry.endswith(".xcassets") or entry.endswith(".bundle"):
                node.files.append(rel_path)
            else:
                child = scan(rel_path)
                if child.files or child.children:
                    node.children.append(child)
        else:
            node.files.append(rel_path)
    return node


def collect(node: Node, out: list[str]) -> None:
    out.extend(node.files)
    for child in node.children:
        collect(child, out)


def q(value: str) -> str:
    """Quote a pbxproj value when it is not a bare identifier."""
    safe = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./")
    if value and all(c in safe for c in value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def settings_block(settings: dict, indent: str) -> str:
    lines = []
    for key in sorted(settings):
        value = settings[key]
        if isinstance(value, list):
            lines.append(f"{indent}{key} = (")
            for item in value:
                lines.append(f"{indent}\t{q(str(item))},")
            lines.append(f"{indent});")
        else:
            lines.append(f"{indent}{key} = {q(str(value))};")
    return "\n".join(lines)


PROJECT_SETTINGS_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "macosx",
    "SWIFT_STRICT_CONCURRENCY": "complete",
}

PROJECT_SETTINGS_DEBUG = dict(PROJECT_SETTINGS_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "$(inherited)"],
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})

PROJECT_SETTINGS_RELEASE = dict(PROJECT_SETTINGS_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
})

APP_SETTINGS_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": f"{APP_NAME}/{APP_NAME}.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": BUILD_VERSION,
    "DEVELOPMENT_TEAM": DEVELOPMENT_TEAM,
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
    "INFOPLIST_KEY_LSUIElement": "YES",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "",
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": SWIFT_VERSION,
}

TEST_SETTINGS_COMMON = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD_VERSION,
    "DEVELOPMENT_TEAM": DEVELOPMENT_TEAM,
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + "Tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": SWIFT_VERSION,
    "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP_NAME}.app/Contents/MacOS/{APP_NAME}",
}


def emit_group(node: Node, lines: list[str], is_root_of: str | None = None) -> str:
    """Emit PBXGroup entries depth first, returning this group's identifier."""
    child_ids = [emit_group(c, lines) for c in node.children]
    entries = []
    for cid, child in zip(child_ids, node.children):
        entries.append((cid, child.name))
    for f in node.files:
        entries.append((oid("file:" + f), os.path.basename(f)))
    gid = oid("group:" + node.rel)
    lines.append(f"\t\t{gid} /* {node.name} */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for cid, name in entries:
        lines.append(f"\t\t\t\t{cid} /* {name} */,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tpath = {q(node.name)};")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")
    return gid


def main() -> int:
    trees = {name: scan(name) for name in SOURCE_ROOTS}
    files: dict[str, list[str]] = {}
    for name, tree in trees.items():
        collected: list[str] = []
        collect(tree, collected)
        files[name] = collected

    app_files = files[APP_NAME]
    test_files = files[TEST_NAME]

    L: list[str] = []
    L.append("// !$*UTF8*$!")
    L.append("{")
    L.append("\tarchiveVersion = 1;")
    L.append("\tclasses = {")
    L.append("\t};")
    L.append("\tobjectVersion = 56;")
    L.append("\tobjects = {")

    # ---- PBXBuildFile -----------------------------------------------------
    L.append("")
    L.append("/* Begin PBXBuildFile section */")
    for target, flist in ((APP_NAME, app_files), (TEST_NAME, test_files)):
        for f in flist:
            phase = build_phase_for(f)
            if not phase:
                continue
            bid = oid(f"build:{target}:{f}")
            fid = oid("file:" + f)
            base = os.path.basename(f)
            L.append(f"\t\t{bid} /* {base} in {phase} */ = {{isa = PBXBuildFile; fileRef = {fid} /* {base} */; }};")
    L.append("/* End PBXBuildFile section */")

    # ---- PBXContainerItemProxy -------------------------------------------
    proxy_id = oid("proxy:app")
    project_id = oid("project")
    app_target_id = oid("target:app")
    test_target_id = oid("target:test")
    L.append("")
    L.append("/* Begin PBXContainerItemProxy section */")
    L.append(f"\t\t{proxy_id} /* PBXContainerItemProxy */ = {{")
    L.append("\t\t\tisa = PBXContainerItemProxy;")
    L.append(f"\t\t\tcontainerPortal = {project_id} /* Project object */;")
    L.append("\t\t\tproxyType = 1;")
    L.append(f"\t\t\tremoteGlobalIDString = {app_target_id};")
    L.append(f"\t\t\tremoteInfo = {APP_NAME};")
    L.append("\t\t};")
    L.append("/* End PBXContainerItemProxy section */")

    # ---- PBXFileReference -------------------------------------------------
    app_product_id = oid("product:app")
    test_product_id = oid("product:test")
    L.append("")
    L.append("/* Begin PBXFileReference section */")
    L.append(f"\t\t{app_product_id} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    L.append(f"\t\t{test_product_id} /* {TEST_NAME}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TEST_NAME}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for flist in (app_files, test_files):
        for f in flist:
            fid = oid("file:" + f)
            base = os.path.basename(f)
            L.append(f"\t\t{fid} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(f)}; path = {q(base)}; sourceTree = \"<group>\"; }};")
    L.append("/* End PBXFileReference section */")

    # ---- PBXFrameworksBuildPhase -----------------------------------------
    app_frameworks = oid("frameworks:app")
    test_frameworks = oid("frameworks:test")
    L.append("")
    L.append("/* Begin PBXFrameworksBuildPhase section */")
    for pid, label in ((app_frameworks, APP_NAME), (test_frameworks, TEST_NAME)):
        L.append(f"\t\t{pid} /* Frameworks */ = {{")
        L.append("\t\t\tisa = PBXFrameworksBuildPhase;")
        L.append("\t\t\tbuildActionMask = 2147483647;")
        L.append("\t\t\tfiles = (")
        L.append("\t\t\t);")
        L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        L.append("\t\t};")
    L.append("/* End PBXFrameworksBuildPhase section */")

    # ---- PBXGroup ---------------------------------------------------------
    group_lines: list[str] = []
    app_group_id = emit_group(trees[APP_NAME], group_lines)
    test_group_id = emit_group(trees[TEST_NAME], group_lines)
    products_id = oid("group:Products")
    root_group_id = oid("group:root")

    group_lines.append(f"\t\t{products_id} /* Products */ = {{")
    group_lines.append("\t\t\tisa = PBXGroup;")
    group_lines.append("\t\t\tchildren = (")
    group_lines.append(f"\t\t\t\t{app_product_id} /* {APP_NAME}.app */,")
    group_lines.append(f"\t\t\t\t{test_product_id} /* {TEST_NAME}.xctest */,")
    group_lines.append("\t\t\t);")
    group_lines.append("\t\t\tname = Products;")
    group_lines.append("\t\t\tsourceTree = \"<group>\";")
    group_lines.append("\t\t};")

    group_lines.append(f"\t\t{root_group_id} = {{")
    group_lines.append("\t\t\tisa = PBXGroup;")
    group_lines.append("\t\t\tchildren = (")
    group_lines.append(f"\t\t\t\t{app_group_id} /* {APP_NAME} */,")
    group_lines.append(f"\t\t\t\t{test_group_id} /* {TEST_NAME} */,")
    group_lines.append(f"\t\t\t\t{products_id} /* Products */,")
    group_lines.append("\t\t\t);")
    group_lines.append("\t\t\tsourceTree = \"<group>\";")
    group_lines.append("\t\t};")

    L.append("")
    L.append("/* Begin PBXGroup section */")
    L.extend(group_lines)
    L.append("/* End PBXGroup section */")

    # ---- PBXNativeTarget --------------------------------------------------
    app_sources = oid("sources:app")
    app_resources = oid("resources:app")
    test_sources = oid("sources:test")
    test_resources = oid("resources:test")
    app_conf_list = oid("conflist:app")
    test_conf_list = oid("conflist:test")
    project_conf_list = oid("conflist:project")
    dependency_id = oid("dependency:test->app")

    L.append("")
    L.append("/* Begin PBXNativeTarget section */")
    L.append(f"\t\t{app_target_id} /* {APP_NAME} */ = {{")
    L.append("\t\t\tisa = PBXNativeTarget;")
    L.append(f"\t\t\tbuildConfigurationList = {app_conf_list} /* Build configuration list for PBXNativeTarget \"{APP_NAME}\" */;")
    L.append("\t\t\tbuildPhases = (")
    L.append(f"\t\t\t\t{app_sources} /* Sources */,")
    L.append(f"\t\t\t\t{app_frameworks} /* Frameworks */,")
    L.append(f"\t\t\t\t{app_resources} /* Resources */,")
    L.append("\t\t\t);")
    L.append("\t\t\tbuildRules = (")
    L.append("\t\t\t);")
    L.append("\t\t\tdependencies = (")
    L.append("\t\t\t);")
    L.append(f"\t\t\tname = {APP_NAME};")
    L.append(f"\t\t\tproductName = {APP_NAME};")
    L.append(f"\t\t\tproductReference = {app_product_id} /* {APP_NAME}.app */;")
    L.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    L.append("\t\t};")

    L.append(f"\t\t{test_target_id} /* {TEST_NAME} */ = {{")
    L.append("\t\t\tisa = PBXNativeTarget;")
    L.append(f"\t\t\tbuildConfigurationList = {test_conf_list} /* Build configuration list for PBXNativeTarget \"{TEST_NAME}\" */;")
    L.append("\t\t\tbuildPhases = (")
    L.append(f"\t\t\t\t{test_sources} /* Sources */,")
    L.append(f"\t\t\t\t{test_frameworks} /* Frameworks */,")
    L.append(f"\t\t\t\t{test_resources} /* Resources */,")
    L.append("\t\t\t);")
    L.append("\t\t\tbuildRules = (")
    L.append("\t\t\t);")
    L.append("\t\t\tdependencies = (")
    L.append(f"\t\t\t\t{dependency_id} /* PBXTargetDependency */,")
    L.append("\t\t\t);")
    L.append(f"\t\t\tname = {TEST_NAME};")
    L.append(f"\t\t\tproductName = {TEST_NAME};")
    L.append(f"\t\t\tproductReference = {test_product_id} /* {TEST_NAME}.xctest */;")
    L.append("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    L.append("\t\t};")
    L.append("/* End PBXNativeTarget section */")

    # ---- PBXProject -------------------------------------------------------
    L.append("")
    L.append("/* Begin PBXProject section */")
    L.append(f"\t\t{project_id} /* Project object */ = {{")
    L.append("\t\t\tisa = PBXProject;")
    L.append("\t\t\tattributes = {")
    L.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    L.append("\t\t\t\tLastSwiftUpdateCheck = 2660;")
    L.append("\t\t\t\tLastUpgradeCheck = 2660;")
    L.append("\t\t\t\tTargetAttributes = {")
    L.append(f"\t\t\t\t\t{app_target_id} = {{")
    L.append("\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;")
    L.append("\t\t\t\t\t};")
    L.append(f"\t\t\t\t\t{test_target_id} = {{")
    L.append("\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;")
    L.append(f"\t\t\t\t\t\tTestTargetID = {app_target_id};")
    L.append("\t\t\t\t\t};")
    L.append("\t\t\t\t};")
    L.append("\t\t\t};")
    L.append(f"\t\t\tbuildConfigurationList = {project_conf_list} /* Build configuration list for PBXProject \"{APP_NAME}\" */;")
    L.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    L.append("\t\t\tdevelopmentRegion = en;")
    L.append("\t\t\thasScannedForEncodings = 0;")
    L.append("\t\t\tknownRegions = (")
    L.append("\t\t\t\ten,")
    L.append("\t\t\t\tBase,")
    L.append("\t\t\t);")
    L.append(f"\t\t\tmainGroup = {root_group_id};")
    L.append(f"\t\t\tproductRefGroup = {products_id} /* Products */;")
    L.append("\t\t\tprojectDirPath = \"\";")
    L.append("\t\t\tprojectRoot = \"\";")
    L.append("\t\t\ttargets = (")
    L.append(f"\t\t\t\t{app_target_id} /* {APP_NAME} */,")
    L.append(f"\t\t\t\t{test_target_id} /* {TEST_NAME} */,")
    L.append("\t\t\t);")
    L.append("\t\t};")
    L.append("/* End PBXProject section */")

    # ---- Resources / Sources phases --------------------------------------
    def phase(pid: str, isa: str, label: str, target: str, flist: list[str], want: str) -> None:
        L.append(f"\t\t{pid} /* {label} */ = {{")
        L.append(f"\t\t\tisa = {isa};")
        L.append("\t\t\tbuildActionMask = 2147483647;")
        L.append("\t\t\tfiles = (")
        for f in flist:
            if build_phase_for(f) == want:
                L.append(f"\t\t\t\t{oid(f'build:{target}:{f}')} /* {os.path.basename(f)} in {want} */,")
        L.append("\t\t\t);")
        L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        L.append("\t\t};")

    L.append("")
    L.append("/* Begin PBXResourcesBuildPhase section */")
    phase(app_resources, "PBXResourcesBuildPhase", "Resources", APP_NAME, app_files, "Resources")
    phase(test_resources, "PBXResourcesBuildPhase", "Resources", TEST_NAME, test_files, "Resources")
    L.append("/* End PBXResourcesBuildPhase section */")

    L.append("")
    L.append("/* Begin PBXSourcesBuildPhase section */")
    phase(app_sources, "PBXSourcesBuildPhase", "Sources", APP_NAME, app_files, "Sources")
    phase(test_sources, "PBXSourcesBuildPhase", "Sources", TEST_NAME, test_files, "Sources")
    L.append("/* End PBXSourcesBuildPhase section */")

    # ---- PBXTargetDependency ---------------------------------------------
    L.append("")
    L.append("/* Begin PBXTargetDependency section */")
    L.append(f"\t\t{dependency_id} /* PBXTargetDependency */ = {{")
    L.append("\t\t\tisa = PBXTargetDependency;")
    L.append(f"\t\t\ttarget = {app_target_id} /* {APP_NAME} */;")
    L.append(f"\t\t\ttargetProxy = {proxy_id} /* PBXContainerItemProxy */;")
    L.append("\t\t};")
    L.append("/* End PBXTargetDependency section */")

    # ---- XCBuildConfiguration ---------------------------------------------
    L.append("")
    L.append("/* Begin XCBuildConfiguration section */")

    def config(cid: str, name: str, settings: dict) -> None:
        L.append(f"\t\t{cid} /* {name} */ = {{")
        L.append("\t\t\tisa = XCBuildConfiguration;")
        L.append("\t\t\tbuildSettings = {")
        L.append(settings_block(settings, "\t\t\t\t"))
        L.append("\t\t\t};")
        L.append(f"\t\t\tname = {name};")
        L.append("\t\t};")

    config(oid("config:project:Debug"), "Debug", PROJECT_SETTINGS_DEBUG)
    config(oid("config:project:Release"), "Release", PROJECT_SETTINGS_RELEASE)
    config(oid("config:app:Debug"), "Debug", APP_SETTINGS_COMMON)
    config(oid("config:app:Release"), "Release", APP_SETTINGS_COMMON)
    config(oid("config:test:Debug"), "Debug", TEST_SETTINGS_COMMON)
    config(oid("config:test:Release"), "Release", TEST_SETTINGS_COMMON)
    L.append("/* End XCBuildConfiguration section */")

    # ---- XCConfigurationList ----------------------------------------------
    L.append("")
    L.append("/* Begin XCConfigurationList section */")

    def conf_list(lid: str, label: str, debug: str, release: str) -> None:
        L.append(f"\t\t{lid} /* Build configuration list for {label} */ = {{")
        L.append("\t\t\tisa = XCConfigurationList;")
        L.append("\t\t\tbuildConfigurations = (")
        L.append(f"\t\t\t\t{debug} /* Debug */,")
        L.append(f"\t\t\t\t{release} /* Release */,")
        L.append("\t\t\t);")
        L.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        L.append("\t\t\tdefaultConfigurationName = Release;")
        L.append("\t\t};")

    conf_list(project_conf_list, f"PBXProject \"{APP_NAME}\"", oid("config:project:Debug"), oid("config:project:Release"))
    conf_list(app_conf_list, f"PBXNativeTarget \"{APP_NAME}\"", oid("config:app:Debug"), oid("config:app:Release"))
    conf_list(test_conf_list, f"PBXNativeTarget \"{TEST_NAME}\"", oid("config:test:Debug"), oid("config:test:Release"))
    L.append("/* End XCConfigurationList section */")

    L.append("\t};")
    L.append(f"\trootObject = {project_id} /* Project object */;")
    L.append("}")

    proj_dir = os.path.join(ROOT, f"{APP_NAME}.xcodeproj")
    os.makedirs(os.path.join(proj_dir, "xcshareddata", "xcschemes"), exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(L) + "\n")

    scheme = SCHEME_TEMPLATE.format(
        app_target=app_target_id,
        test_target=test_target_id,
        app_name=APP_NAME,
        test_name=TEST_NAME,
        container=f"container:{APP_NAME}.xcodeproj",
    )
    with open(os.path.join(proj_dir, "xcshareddata", "xcschemes", f"{APP_NAME}.xcscheme"), "w", encoding="utf-8") as fh:
        fh.write(scheme)

    print(f"Generated {APP_NAME}.xcodeproj  ({len(app_files)} app files, {len(test_files)} test files)")
    return 0


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2660" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "{app_name}.app"
               BlueprintName = "{app_name}"
               ReferencedContainer = "{container}">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "{test_name}.xctest"
               BlueprintName = "{test_name}"
               ReferencedContainer = "{container}">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{app_name}.app"
            BlueprintName = "{app_name}"
            ReferencedContainer = "{container}">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{app_name}.app"
            BlueprintName = "{app_name}"
            ReferencedContainer = "{container}">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    sys.exit(main())
