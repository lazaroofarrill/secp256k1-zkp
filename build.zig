const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    const enable_ecdh = b.option(bool, "enable-ecdh", "Enable ECDH module.") orelse true;
    const enable_recovery = b.option(bool, "enable-recovery", "Enable ECDSA pubkey recovery module.") orelse false;
    var enable_extrakeys = b.option(bool, "enable-extrakeys", "Enable extrakeys module.") orelse true;
    var enable_schnorrsig = b.option(bool, "enable-schnorrsig", "Enable schnorrsig module.") orelse true;
    const enable_musig = b.option(bool, "enable-musig", "Enable musig module.") orelse true;
    const enable_ellswift = b.option(bool, "enable-ellswift", "Enable ElligatorSwift module.") orelse true;
    var enable_generator = b.option(bool, "enable-generator", "Enable NUMS generator module.") orelse true;
    var enable_rangeproof = b.option(bool, "enable-rangeproof", "Enable Range proof module.") orelse true;
    const enable_surjectionproof = b.option(bool, "enable-surjectionproof", "Enable Surjection proof module.") orelse true;
    const enable_whitelist = b.option(bool, "enable-whitelist", "Enable key whitelist module.") orelse true;
    const enable_ecdsa_adaptor = b.option(bool, "enable-ecdsa-adaptor", "Enable ecdsa adaptor signatures module.") orelse true;
    const enable_ecdsa_s2c = b.option(bool, "enable-ecdsa-s2c", "Enable ECDSA sign-to-contract module.") orelse true;
    const enable_bppp = b.option(bool, "enable-bppp", "Enable Bulletproofs++ module.") orelse true;
    const enable_schnorrsig_halfagg = b.option(bool, "enable-schnorrsig-halfagg", "Enable schnorrsig half-aggregation module.") orelse true;

    // Parameters
    const ecmult_window_size = b.option(u32, "ecmult-window-size", "Window size for ecmult precomputation for verification (2-24). Default 15.") orelse 15;
    const ecmult_gen_kb = b.option(u32, "ecmult-gen-kb", "Size of precomputed table for signing (2, 22, 86). Default 86.") orelse 86;

    // Dependencies (Topological Sort from CMake)
    if (enable_schnorrsig_halfagg) {
        enable_schnorrsig = true;
    }
    if (enable_bppp) {
        enable_generator = true;
    }
    if (enable_whitelist) {
        enable_rangeproof = true;
    }
    if (enable_surjectionproof) {
        enable_rangeproof = true;
    }
    if (enable_rangeproof) {
        enable_generator = true;
    }
    if (enable_musig) {
        enable_schnorrsig = true;
    }
    if (enable_schnorrsig) {
        enable_extrakeys = true;
    }

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "secp256k1",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    lib.root_module.addIncludePath(b.path("."));
    lib.root_module.addIncludePath(b.path("include"));
    lib.root_module.addIncludePath(b.path("src"));

    const c_flags = &[_][]const u8{
        "-std=c90",
        "-Wall",
        "-Wextra",
        "-Wcast-align",
        "-Wnested-externs",
        "-Wshadow",
        "-Wstrict-prototypes",
        "-Wundef",
    };

    for (&[_][]const u8{
        "src/secp256k1.c",
        "src/precomputed_ecmult.c",
        "src/precomputed_ecmult_gen.c",
    }) |file| {
        lib.root_module.addCSourceFile(.{
            .file = b.path(file),
            .flags = c_flags,
        });
    }

    // C Macros for modules
    if (enable_ecdh) lib.root_module.addCMacro("ENABLE_MODULE_ECDH", "1");
    if (enable_recovery) lib.root_module.addCMacro("ENABLE_MODULE_RECOVERY", "1");
    if (enable_extrakeys) lib.root_module.addCMacro("ENABLE_MODULE_EXTRAKEYS", "1");
    if (enable_schnorrsig) lib.root_module.addCMacro("ENABLE_MODULE_SCHNORRSIG", "1");
    if (enable_musig) lib.root_module.addCMacro("ENABLE_MODULE_MUSIG", "1");
    if (enable_ellswift) lib.root_module.addCMacro("ENABLE_MODULE_ELLSWIFT", "1");
    if (enable_generator) lib.root_module.addCMacro("ENABLE_MODULE_GENERATOR", "1");
    if (enable_rangeproof) lib.root_module.addCMacro("ENABLE_MODULE_RANGEPROOF", "1");
    if (enable_surjectionproof) lib.root_module.addCMacro("ENABLE_MODULE_SURJECTIONPROOF", "1");
    if (enable_whitelist) lib.root_module.addCMacro("ENABLE_MODULE_WHITELIST", "1");
    if (enable_ecdsa_adaptor) lib.root_module.addCMacro("ENABLE_MODULE_ECDSA_ADAPTOR", "1");
    if (enable_ecdsa_s2c) lib.root_module.addCMacro("ENABLE_MODULE_ECDSA_S2C", "1");
    if (enable_bppp) lib.root_module.addCMacro("ENABLE_MODULE_BPPP", "1");
    if (enable_schnorrsig_halfagg) lib.root_module.addCMacro("ENABLE_MODULE_SCHNORRSIG_HALFAGG", "1");

    // Parameters
    lib.root_module.addCMacro("ECMULT_WINDOW_SIZE", b.fmt("{d}", .{ecmult_window_size}));

    if (ecmult_gen_kb == 2) {
        lib.root_module.addCMacro("COMB_BLOCKS", "2");
        lib.root_module.addCMacro("COMB_TEETH", "5");
    } else if (ecmult_gen_kb == 22) {
        lib.root_module.addCMacro("COMB_BLOCKS", "11");
        lib.root_module.addCMacro("COMB_TEETH", "6");
    } else if (ecmult_gen_kb == 86) {
        lib.root_module.addCMacro("COMB_BLOCKS", "43");
        lib.root_module.addCMacro("COMB_TEETH", "6");
    } else {
        std.debug.panic("Invalid ecmult_gen_kb value: {d}. Valid choices are 2, 22, 86.", .{ecmult_gen_kb});
    }

    // Assembly
    const cpu_arch = target.result.cpu.arch;
    if (cpu_arch == .x86_64) {
        lib.root_module.addCMacro("USE_ASM_X86_64", "1");
    } else if (cpu_arch == .arm or cpu_arch == .armeb or cpu_arch == .thumb) {
        lib.root_module.addCMacro("USE_EXTERNAL_ASM", "1");
        lib.root_module.addCSourceFile(.{
            .file = b.path("src/asm/field_10x26_arm.s"),
            .flags = &[_][]const u8{},
        });
    }

    lib.installHeader(b.path("include/secp256k1.h"), "secp256k1.h");
    lib.installHeader(b.path("include/secp256k1_preallocated.h"), "secp256k1_preallocated.h");

    if (enable_ecdh) lib.installHeader(b.path("include/secp256k1_ecdh.h"), "secp256k1_ecdh.h");
    if (enable_recovery) lib.installHeader(b.path("include/secp256k1_recovery.h"), "secp256k1_recovery.h");
    if (enable_extrakeys) lib.installHeader(b.path("include/secp256k1_extrakeys.h"), "secp256k1_extrakeys.h");
    if (enable_schnorrsig) lib.installHeader(b.path("include/secp256k1_schnorrsig.h"), "secp256k1_schnorrsig.h");
    if (enable_musig) lib.installHeader(b.path("include/secp256k1_musig.h"), "secp256k1_musig.h");
    if (enable_ellswift) lib.installHeader(b.path("include/secp256k1_ellswift.h"), "secp256k1_ellswift.h");
    if (enable_generator) lib.installHeader(b.path("include/secp256k1_generator.h"), "secp256k1_generator.h");
    if (enable_rangeproof) lib.installHeader(b.path("include/secp256k1_rangeproof.h"), "secp256k1_rangeproof.h");
    if (enable_surjectionproof) lib.installHeader(b.path("include/secp256k1_surjectionproof.h"), "secp256k1_surjectionproof.h");
    if (enable_whitelist) lib.installHeader(b.path("include/secp256k1_whitelist.h"), "secp256k1_whitelist.h");
    if (enable_ecdsa_adaptor) lib.installHeader(b.path("include/secp256k1_ecdsa_adaptor.h"), "secp256k1_ecdsa_adaptor.h");
    if (enable_ecdsa_s2c) lib.installHeader(b.path("include/secp256k1_ecdsa_s2c.h"), "secp256k1_ecdsa_s2c.h");
    if (enable_bppp) lib.installHeader(b.path("include/secp256k1_bppp.h"), "secp256k1_bppp.h");
    if (enable_schnorrsig_halfagg) lib.installHeader(b.path("include/secp256k1_schnorrsig_halfagg.h"), "secp256k1_schnorrsig_halfagg.h");

    b.installArtifact(lib);
}
