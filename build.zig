const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.option(bool, "tests", "Build tests [default: false]") orelse false;
    const ssl = b.option(bool, "ssl", "Build cobalt with OpenSSL support [default: false]") orelse false;

    const boost = boostLibraries(b, target);
    const lib = b.addStaticLibrary(.{
        .name = "cobalt",
        .target = target,
        .optimize = optimize,
    });
    switch (optimize) {
        .Debug, .ReleaseSafe => lib.bundle_compiler_rt = true,
        else => lib.root_module.strip = true,
    }
    lib.pie = true;
    lib.addIncludePath(b.path("include"));
    for (boost.root_module.include_dirs.items) |include| {
        lib.root_module.include_dirs.append(b.allocator, include) catch {};
    }
    lib.defineCMacro("BOOST_COBALT_SOURCE", null);
    lib.defineCMacro("BOOST_COBALT_USE_BOOST_CONTAINER_PMR", null);
    lib.addCSourceFiles(.{
        .files = &.{
            "src/channel.cpp",
            "src/detail/exception.cpp",
            "src/detail/util.cpp",
            "src/error.cpp",
            "src/main.cpp",
            "src/this_thread.cpp",
            "src/thread.cpp",
        },
        .flags = cxxFlags,
    });
    lib.linkLibrary(boost);
    if (lib.rootModuleTarget().abi == .msvc)
        lib.linkLibC()
    else
        lib.linkLibCpp();
    lib.installHeadersDirectory(b.path("include"), "", .{});
    lib.step.dependOn(&boost.step);
    b.installArtifact(lib);

    if (tests) {
        // buildTest(b, .{
        //     .path = "example/channel.cpp",
        //     .lib = lib,
        // });
        buildTest(b, .{
            .path = "example/delay.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/delay_op.cpp",
            .lib = lib,
        });
        if (ssl) buildTest(b, .{
            .path = "example/http.cpp",
            .lib = lib,
        });
        if (ssl) buildTest(b, .{
            .path = "example/ticker.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/thread_pool.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/spsc.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/thread.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/signals.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/outcome.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/echo_server.cpp",
            .lib = lib,
        });
        if (ssl) buildTest(b, .{
            .path = "example/http_server.cpp",
            .lib = lib,
        });
        // need nanobinding
        // buildTest(b, .{
        //     .path = "example/python.cpp",
        //     .lib = lib,
        // });
        buildTest(b, .{
            .path = "bench/post.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "bench/immediate.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "bench/parallel.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "bench/monotonic.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "bench/channel.cpp",
            .lib = lib,
        });
    }
}

const cxxFlags: []const []const u8 = &.{
    "-Wall",
    "-Wextra",
    "-std=gnu++23",
    "-fexperimental-library", // std::ranges and others...
};

fn buildTest(b: *std.Build, info: BuildInfo) void {
    const test_exe = b.addExecutable(.{
        .name = info.filename(),
        .optimize = info.lib.root_module.optimize.?,
        .target = info.lib.root_module.resolved_target.?,
    });
    for (info.lib.root_module.include_dirs.items) |include| {
        test_exe.root_module.include_dirs.append(b.allocator, include) catch {};
    }
    if (std.mem.startsWith(u8, info.filename(), "http")) {
        test_exe.linkSystemLibrary("ssl");
        test_exe.linkSystemLibrary("crypto");
    }
    if (std.mem.startsWith(u8, info.filename(), "tick")) {
        test_exe.linkSystemLibrary("ssl");
        test_exe.linkSystemLibrary("crypto");
        const context_dep = b.dependency("context", .{
            .optimize = info.lib.root_module.optimize.?,
            .target = info.lib.root_module.resolved_target.?,
        });
        const context = context_dep.artifact("context");
        for (context.root_module.include_dirs.items) |include| {
            test_exe.root_module.include_dirs.append(b.allocator, include) catch {};
        }
        test_exe.linkLibrary(context);
        const unordered_dep = b.dependency("unordered", .{
            .optimize = info.lib.root_module.optimize.?,
            .target = info.lib.root_module.resolved_target.?,
        });
        const unordered_include = unordered_dep.path("");
        test_exe.addIncludePath(unordered_include);
    }

    test_exe.defineCMacro("BOOST_COBALT_USE_BOOST_CONTAINER_PMR", null);
    test_exe.step.dependOn(&info.lib.step);
    test_exe.addIncludePath(b.path("test"));
    test_exe.addCSourceFile(.{
        .file = b.path(info.path),
        .flags = cxxFlags,
    });
    if (test_exe.rootModuleTarget().os.tag == .windows) {
        test_exe.linkSystemLibrary2("ws2_32", .{ .use_pkg_config = .no });
        test_exe.linkSystemLibrary2("mswsock", .{ .use_pkg_config = .no });
    }
    test_exe.linkLibrary(info.lib);
    if (test_exe.rootModuleTarget().abi == .msvc)
        test_exe.linkLibC()
    else
        test_exe.linkLibCpp();
    b.installArtifact(test_exe);

    const run_cmd = b.addRunArtifact(test_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(
        info.filename(),
        b.fmt("Run the {s} test", .{info.filename()}),
    );
    run_step.dependOn(&run_cmd.step);
}

const BuildInfo = struct {
    lib: *std.Build.Step.Compile,
    path: []const u8,

    fn filename(self: BuildInfo) []const u8 {
        var split = std.mem.splitAny(u8, std.fs.path.basename(self.path), ".");
        return split.first();
    }
};

fn boostLibraries(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Step.Compile {
    const beast_dep = b.dependency("beast", .{
        .target = target,
        .optimize = .ReleaseFast,
    });
    const beast = beast_dep.artifact("beast");

    const lib = b.addStaticLibrary(.{
        .name = "boost",
        .target = target,
        .optimize = .ReleaseFast,
    });
    for (beast.root_module.include_dirs.items) |include| {
        lib.root_module.include_dirs.append(b.allocator, include) catch {};
    }
    lib.linkLibrary(beast);

    const boostCircBuffer = b.dependency("circular_buffer", .{}).path("");
    const boostLeaf = b.dependency("leaf", .{}).path("");
    const boostFunction = b.dependency("function", .{}).path("");
    const boostURL = b.dependency("url", .{}).path("");
    const boostSignals = b.dependency("signals2", .{}).path("");
    const boostVariant = b.dependency("variant", .{}).path("");
    const boostTypeIndex = b.dependency("type_index", .{}).path("");
    const boostInteger = b.dependency("integer", .{}).path("");
    const boostParameter = b.dependency("parameter", .{}).path("");
    const boostCallableTraits = b.dependency("callable_traits", .{}).path("");
    const boostLockFree = b.dependency("lockfree", .{}).path("");

    lib.addCSourceFiles(.{
        .root = boostURL,
        .files = &.{
            "src/authority_view.cpp",
            "src/decode_view.cpp",
            "src/detail/any_params_iter.cpp",
            "src/detail/any_segments_iter.cpp",
            "src/detail/decode.cpp",
            "src/detail/except.cpp",
            "src/detail/format_args.cpp",
            "src/detail/normalize.cpp",
            "src/detail/params_iter_impl.cpp",
            "src/detail/pattern.cpp",
            "src/detail/pct_format.cpp",
            "src/detail/replacement_field_rule.cpp",
            "src/detail/segments_iter_impl.cpp",
            "src/detail/url_impl.cpp",
            "src/encoding_opts.cpp",
            "src/error.cpp",
            "src/grammar/ci_string.cpp",
            "src/grammar/dec_octet_rule.cpp",
            "src/grammar/delim_rule.cpp",
            "src/grammar/detail/recycled.cpp",
            "src/grammar/error.cpp",
            "src/grammar/literal_rule.cpp",
            "src/grammar/string_view_base.cpp",
            "src/ipv4_address.cpp",
            "src/ipv6_address.cpp",
            "src/params_base.cpp",
            "src/params_encoded_base.cpp",
            "src/params_encoded_ref.cpp",
            "src/params_encoded_view.cpp",
            "src/params_ref.cpp",
            "src/params_view.cpp",
            "src/parse.cpp",
            "src/parse_path.cpp",
            "src/parse_query.cpp",
            "src/pct_string_view.cpp",
            "src/rfc/absolute_uri_rule.cpp",
            "src/rfc/authority_rule.cpp",
            "src/rfc/detail/h16_rule.cpp",
            "src/rfc/detail/hier_part_rule.cpp",
            "src/rfc/detail/host_rule.cpp",
            "src/rfc/detail/ip_literal_rule.cpp",
            "src/rfc/detail/ipv6_addrz_rule.cpp",
            "src/rfc/detail/ipvfuture_rule.cpp",
            "src/rfc/detail/port_rule.cpp",
            "src/rfc/detail/relative_part_rule.cpp",
            "src/rfc/detail/scheme_rule.cpp",
            "src/rfc/detail/userinfo_rule.cpp",
            "src/rfc/ipv4_address_rule.cpp",
            "src/rfc/ipv6_address_rule.cpp",
            "src/rfc/origin_form_rule.cpp",
            "src/rfc/query_rule.cpp",
            "src/rfc/relative_ref_rule.cpp",
            "src/rfc/uri_reference_rule.cpp",
            "src/rfc/uri_rule.cpp",
            "src/scheme.cpp",
            "src/segments_base.cpp",
            "src/segments_encoded_base.cpp",
            "src/segments_encoded_ref.cpp",
            "src/segments_encoded_view.cpp",
            "src/segments_ref.cpp",
            "src/segments_view.cpp",
            "src/static_url.cpp",
            "src/url.cpp",
            "src/url_base.cpp",
            "src/url_view.cpp",
            "src/url_view_base.cpp",
        },
        .flags = cxxFlags,
    });
    if (lib.rootModuleTarget().abi != .msvc)
        lib.linkLibCpp()
    else
        lib.linkLibC();

    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostCircBuffer.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostLeaf.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostFunction.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostURL.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostInteger.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostSignals.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostCallableTraits.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostTypeIndex.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostParameter.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostLockFree.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostVariant.getPath(b), "include" }) });

    return lib;
}
