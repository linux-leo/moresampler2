const std = @import("std");

const c = @cImport({
    @cDefine("FP_TYPE", "float");
    @cInclude("ciglet/ciglet.h");
    @cInclude("libllsm/llsm.h");
    @cInclude("libpyin/pyin.h");
    @cInclude("libgvps/gvps.h");
});

const FP = f32;
const version = "0.2.5";

fn toAny(ptr: anytype) ?*anyopaque {
    return @as(?*anyopaque, @ptrCast(ptr));
}

fn toDestructor(func: anytype) c.llsm_fdestructor {
    return @as(c.llsm_fdestructor, @ptrCast(func));
}

fn toCopy(func: anytype) c.llsm_fcopy {
    return @as(c.llsm_fcopy, @ptrCast(func));
}

fn attach(container: *c.llsm_container, index: c_int, ptr: ?*anyopaque, dtor: c.llsm_fdestructor, copy: c.llsm_fcopy) void {
    c.llsm_container_attach_(container, index, ptr, dtor, copy);
}

fn alignedPtr(comptime T: type, ptr: ?*anyopaque) ?*T {
    return if (ptr) |p| @as(*T, @ptrCast(@alignCast(p))) else null;
}

fn alignedManyPtr(comptime T: type, ptr: ?*anyopaque) ?[*]T {
    return if (ptr) |p| @as([*]T, @ptrCast(@alignCast(p))) else null;
}

inline fn min(a: anytype, b: anytype) @TypeOf(a, b) {
    return if (a < b) a else b;
}

inline fn max(a: anytype, b: anytype) @TypeOf(a, b) {
    return if (a > b) a else b;
}

inline fn linterp(a: FP, b: FP, ratio: FP) FP {
    return a + (b - a) * ratio;
}

fn linterpc(a: FP, b: FP, ratio: FP) FP {
    const ax = @as(FP, @floatCast(std.math.cos(@as(f64, a))));
    const ay = @as(FP, @floatCast(std.math.sin(@as(f64, a))));
    const bx = @as(FP, @floatCast(std.math.cos(@as(f64, b))));
    const by = @as(FP, @floatCast(std.math.sin(@as(f64, b))));
    const cx = linterp(ax, bx, ratio);
    const cy = linterp(ay, by, ratio);
    return @as(FP, @floatCast(std.math.atan2(@as(f64, cy), @as(f64, cx))));
}

fn interp_nmframe(dst: *c.llsm_nmframe, src: *c.llsm_nmframe, ratio: FP, dst_voiced: bool, src_voiced: bool) void {
    _ = dst_voiced;
    _ = src_voiced;
    var i: c_int = 0;
    while (i < dst.*.npsd) : (i += 1) {
        dst.*.psd[@as(usize, @intCast(i))] = linterp(
            dst.*.psd[@as(usize, @intCast(i))],
            src.*.psd[@as(usize, @intCast(i))],
            ratio,
        );
    }

    var b: c_int = 0;
    while (b < dst.*.nchannel) : (b += 1) {
        const srceenv = src.*.eenv[@as(usize, @intCast(b))].?;
        const dsteenv = dst.*.eenv[@as(usize, @intCast(b))].?;
        dst.*.edc[@as(usize, @intCast(b))] = linterp(
            dst.*.edc[@as(usize, @intCast(b))],
            src.*.edc[@as(usize, @intCast(b))],
            ratio,
        );

        const b_minnhar = min(srceenv.*.nhar, dsteenv.*.nhar);
        const b_maxnhar = max(srceenv.*.nhar, dsteenv.*.nhar);
        if (dsteenv.*.nhar < b_maxnhar) {
            const new_ampl = c.realloc(dsteenv.*.ampl, @sizeOf(FP) * @as(usize, @intCast(b_maxnhar)));
            const new_phse = c.realloc(dsteenv.*.phse, @sizeOf(FP) * @as(usize, @intCast(b_maxnhar)));
            if (new_ampl == null or new_phse == null) return;
            dsteenv.*.ampl = @as([*]FP, @ptrCast(@alignCast(new_ampl)));
            dsteenv.*.phse = @as([*]FP, @ptrCast(@alignCast(new_phse)));
        }
        var j: c_int = 0;
        while (j < b_minnhar) : (j += 1) {
            const idx = @as(usize, @intCast(j));
            dsteenv.*.ampl[idx] = linterp(dsteenv.*.ampl[idx], srceenv.*.ampl[idx], ratio);
            dsteenv.*.phse[idx] = linterpc(dsteenv.*.phse[idx], srceenv.*.phse[idx], ratio);
        }
        if (b_maxnhar == srceenv.*.nhar) {
            var k: c_int = b_minnhar;
            while (k < b_maxnhar) : (k += 1) {
                const idx = @as(usize, @intCast(k));
                dsteenv.*.ampl[idx] = srceenv.*.ampl[idx];
                dsteenv.*.phse[idx] = srceenv.*.phse[idx];
            }
        }
        dsteenv.*.nhar = b_maxnhar;
    }
}

fn write_conf(file: *c.FILE, conf: *c.llsm_aoptions) c_int {
    _ = c.fwrite(&conf.*.thop, @sizeOf(FP), 1, file);
    _ = c.fwrite(&conf.*.maxnhar, @sizeOf(c_int), 1, file);
    _ = c.fwrite(&conf.*.maxnhar_e, @sizeOf(c_int), 1, file);
    _ = c.fwrite(&conf.*.npsd, @sizeOf(c_int), 1, file);
    _ = c.fwrite(&conf.*.nchannel, @sizeOf(c_int), 1, file);
    const chanfreq_len = conf.*.nchannel;
    _ = c.fwrite(&chanfreq_len, @sizeOf(c_int), 1, file);
    _ = c.fwrite(conf.*.chanfreq, @sizeOf(FP), @as(usize, @intCast(chanfreq_len)), file);
    _ = c.fwrite(&conf.*.lip_radius, @sizeOf(FP), 1, file);
    _ = c.fwrite(&conf.*.f0_refine, @sizeOf(FP), 1, file);
    _ = c.fwrite(&conf.*.hm_method, @sizeOf(c_int), 1, file);
    _ = c.fwrite(&conf.*.rel_winsize, @sizeOf(FP), 1, file);
    return 0;
}

fn read_conf(file: *c.FILE, opt: *c.llsm_aoptions) c_int {
    _ = c.fread(&opt.*.thop, @sizeOf(FP), 1, file);
    _ = c.fread(&opt.*.maxnhar, @sizeOf(c_int), 1, file);
    _ = c.fread(&opt.*.maxnhar_e, @sizeOf(c_int), 1, file);
    _ = c.fread(&opt.*.npsd, @sizeOf(c_int), 1, file);
    _ = c.fread(&opt.*.nchannel, @sizeOf(c_int), 1, file);
    var chanfreq_len: c_int = 0;
    _ = c.fread(&chanfreq_len, @sizeOf(c_int), 1, file);
    const chanfreq_raw = c.malloc(@sizeOf(FP) * @as(usize, @intCast(chanfreq_len)));
    if (chanfreq_raw == null) {
        return -1;
    }
    opt.*.chanfreq = @as([*]FP, @ptrCast(@alignCast(chanfreq_raw)));
    _ = c.fread(opt.*.chanfreq, @sizeOf(FP), @as(usize, @intCast(chanfreq_len)), file);
    _ = c.fread(&opt.*.lip_radius, @sizeOf(FP), 1, file);
    _ = c.fread(&opt.*.f0_refine, @sizeOf(FP), 1, file);
    _ = c.fread(&opt.*.hm_method, @sizeOf(c_int), 1, file);
    _ = c.fread(&opt.*.rel_winsize, @sizeOf(FP), 1, file);
    return 0;
}

fn save_llsm(chunk: *c.llsm_chunk, filename: [*:0]const u8, conf: *c.llsm_aoptions, fs: *c_int, nbit: *c_int) c_int {
    const file = c.fopen(filename, "wb") orelse return -1;
    defer _ = c.fclose(file);

    _ = c.fwrite("LLSM2", 1, 5, file);
    var version_local: c_int = 1;
    _ = c.fwrite(&version_local, @sizeOf(c_int), 1, file);

    const nfrm = alignedPtr(c_int, c.llsm_container_get(chunk.*.conf, c.LLSM_CONF_NFRM)) orelse return -1;
    _ = c.fwrite(nfrm, @sizeOf(c_int), 1, file);
    _ = c.fwrite(fs, @sizeOf(c_int), 1, file);
    _ = c.fwrite(nbit, @sizeOf(c_int), 1, file);

    _ = write_conf(file, conf);

    var i: c_int = 0;
    while (i < nfrm.*) : (i += 1) {
        const frame = chunk.*.frames[@as(usize, @intCast(i))];
        const f0_ptr = alignedPtr(FP, c.llsm_container_get(frame, c.LLSM_FRAME_F0)) orelse return -1;
        _ = c.fwrite(f0_ptr, @sizeOf(FP), 1, file);

        const hm = alignedPtr(c.llsm_hmframe, c.llsm_container_get(frame, c.LLSM_FRAME_HM)) orelse return -1;
        _ = c.fwrite(&hm.*.nhar, @sizeOf(c_int), 1, file);
        _ = c.fwrite(hm.*.ampl, @sizeOf(FP), @as(usize, @intCast(hm.*.nhar)), file);
        _ = c.fwrite(hm.*.phse, @sizeOf(FP), @as(usize, @intCast(hm.*.nhar)), file);

        const nm = alignedPtr(c.llsm_nmframe, c.llsm_container_get(frame, c.LLSM_FRAME_NM)) orelse return -1;
        _ = c.fwrite(&nm.*.npsd, @sizeOf(c_int), 1, file);
        _ = c.fwrite(nm.*.psd, @sizeOf(FP), @as(usize, @intCast(nm.*.npsd)), file);

        _ = c.fwrite(&nm.*.nchannel, @sizeOf(c_int), 1, file);
        var j: c_int = 0;
        while (j < nm.*.nchannel) : (j += 1) {
            _ = c.fwrite(&nm.*.edc[@as(usize, @intCast(j))], @sizeOf(FP), 1, file);
            const eenv = nm.*.eenv[@as(usize, @intCast(j))].?;
            _ = c.fwrite(&eenv.*.nhar, @sizeOf(c_int), 1, file);
            _ = c.fwrite(eenv.*.ampl, @sizeOf(FP), @as(usize, @intCast(eenv.*.nhar)), file);
            _ = c.fwrite(eenv.*.phse, @sizeOf(FP), @as(usize, @intCast(eenv.*.nhar)), file);
        }
    }

    return 0;
}

fn read_llsm(filename: [*:0]const u8, nfrm: *c_int, fs: *c_int, nbit: *c_int) ?*c.llsm_chunk {
    const file = c.fopen(filename, "rb") orelse return null;
    defer _ = c.fclose(file);

    var header: [5]u8 = undefined;
    _ = c.fread(&header, 1, 5, file);
    if (!std.mem.eql(u8, header[0..], "LLSM2")) {
        return null;
    }

    var version_local: c_int = 0;
    _ = c.fread(&version_local, @sizeOf(c_int), 1, file);
    if (version_local != 1) {
        return null;
    }
    _ = c.fread(nfrm, @sizeOf(c_int), 1, file);
    _ = c.fread(fs, @sizeOf(c_int), 1, file);
    _ = c.fread(nbit, @sizeOf(c_int), 1, file);

    const aopt = c.llsm_create_aoptions();
    if (read_conf(file, aopt) != 0) {
        c.llsm_delete_aoptions(aopt);
        return null;
    }

    const nyquist = @as(FP, @floatCast(@as(f64, @floatFromInt(fs.*)) / 2.0));
    const conf = c.llsm_aoptions_toconf(aopt, nyquist);
    c.llsm_delete_aoptions(aopt);

    attach(conf, c.LLSM_CONF_NFRM, toAny(c.llsm_create_int(nfrm.*)), toDestructor(&c.llsm_delete_int), toCopy(&c.llsm_copy_int));
    const chunk = c.llsm_create_chunk(conf, nfrm.*);
    c.llsm_delete_container(conf);

    var i: c_int = 0;
    while (i < nfrm.*) : (i += 1) {
        const frame = c.llsm_create_frame(0, 0, 0, 0);

        const f0_raw = c.malloc(@sizeOf(FP)) orelse return null;
        const f0_ptr = @as(*FP, @ptrCast(@alignCast(f0_raw)));
        _ = c.fread(f0_ptr, @sizeOf(FP), 1, file);
        attach(frame, c.LLSM_FRAME_F0, toAny(f0_ptr), toDestructor(&c.free), toCopy(&c.llsm_copy_fp));

        var nhar: c_int = 0;
        _ = c.fread(&nhar, @sizeOf(c_int), 1, file);
        const hm = c.llsm_create_hmframe(nhar);
        _ = c.fread(hm.*.ampl, @sizeOf(FP), @as(usize, @intCast(nhar)), file);
        _ = c.fread(hm.*.phse, @sizeOf(FP), @as(usize, @intCast(nhar)), file);
        attach(frame, c.LLSM_FRAME_HM, toAny(hm), toDestructor(&c.llsm_delete_hmframe), toCopy(&c.llsm_copy_hmframe));

        const nm_raw = c.malloc(@sizeOf(c.llsm_nmframe)) orelse return null;
        const nm = @as(*c.llsm_nmframe, @ptrCast(@alignCast(nm_raw)));
        _ = c.fread(&nm.*.npsd, @sizeOf(c_int), 1, file);
        const psd_raw = c.malloc(@sizeOf(FP) * @as(usize, @intCast(nm.*.npsd))) orelse return null;
        nm.*.psd = @as([*]FP, @ptrCast(@alignCast(psd_raw)));
        _ = c.fread(nm.*.psd, @sizeOf(FP), @as(usize, @intCast(nm.*.npsd)), file);

        _ = c.fread(&nm.*.nchannel, @sizeOf(c_int), 1, file);
        const edc_raw = c.malloc(@sizeOf(FP) * @as(usize, @intCast(nm.*.nchannel))) orelse return null;
        nm.*.edc = @as([*]FP, @ptrCast(@alignCast(edc_raw)));
        const eenv_raw = c.malloc(@sizeOf(?*c.llsm_hmframe) * @as(usize, @intCast(nm.*.nchannel))) orelse return null;
        nm.*.eenv = @as([*]?*c.llsm_hmframe, @ptrCast(@alignCast(eenv_raw)));

        var j: c_int = 0;
        while (j < nm.*.nchannel) : (j += 1) {
            _ = c.fread(&nm.*.edc[@as(usize, @intCast(j))], @sizeOf(FP), 1, file);
            var nhar_e: c_int = 0;
            _ = c.fread(&nhar_e, @sizeOf(c_int), 1, file);
            const eenv = c.llsm_create_hmframe(nhar_e);
            _ = c.fread(eenv.*.ampl, @sizeOf(FP), @as(usize, @intCast(nhar_e)), file);
            _ = c.fread(eenv.*.phse, @sizeOf(FP), @as(usize, @intCast(nhar_e)), file);
            nm.*.eenv[@as(usize, @intCast(j))] = eenv;
        }

        attach(frame, c.LLSM_FRAME_NM, toAny(nm), toDestructor(&c.llsm_delete_nmframe), toCopy(&c.llsm_copy_nmframe));
        chunk.*.frames[@as(usize, @intCast(i))] = frame;
    }

    return chunk;
}

const LOG2DB: FP = 20.0 / 2.3025851;
const EPS: FP = 1e-8;

fn mag2db(x: FP) FP {
    return @as(FP, @floatCast(@log(@as(f64, x)))) * LOG2DB;
}

fn interp_llsm_frame(dst: *c.llsm_container, src: *c.llsm_container, ratio: FP) void {
    const dst_f0_ptr = alignedPtr(FP, c.llsm_container_get(dst, c.LLSM_FRAME_F0)) orelse return;
    const src_f0_ptr = alignedPtr(FP, c.llsm_container_get(src, c.LLSM_FRAME_F0)) orelse return;
    const dst_f0 = dst_f0_ptr.*;
    const src_f0 = src_f0_ptr.*;

    const dst_nm = alignedPtr(c.llsm_nmframe, c.llsm_container_get(dst, c.LLSM_FRAME_NM)) orelse return;
    const src_nm = alignedPtr(c.llsm_nmframe, c.llsm_container_get(src, c.LLSM_FRAME_NM)) orelse return;

    const src_rd_ptr = alignedPtr(FP, c.llsm_container_get(src, c.LLSM_FRAME_RD)) orelse return;
    const dst_rd_ptr = alignedPtr(FP, c.llsm_container_get(dst, c.LLSM_FRAME_RD)) orelse return;

    const dst_vsphse_ptr = alignedManyPtr(FP, c.llsm_container_get(dst, c.LLSM_FRAME_VSPHSE));
    const src_vsphse_ptr = alignedManyPtr(FP, c.llsm_container_get(src, c.LLSM_FRAME_VSPHSE));
    const dst_vtmagn_ptr = alignedManyPtr(FP, c.llsm_container_get(dst, c.LLSM_FRAME_VTMAGN));
    const src_vtmagn_ptr = alignedManyPtr(FP, c.llsm_container_get(src, c.LLSM_FRAME_VTMAGN));

    const voiced: ?*c.llsm_container = if (dst_f0 <= 0 and src_f0 <= 0) null else if (src_f0 > 0) src else dst;
    const bothvoiced = dst_f0 > 0 and src_f0 > 0;

    const dstnhar: c_int = if (dst_vsphse_ptr) |p| c.llsm_fparray_length(p) else 0;
    const srcnhar: c_int = if (src_vsphse_ptr) |p| c.llsm_fparray_length(p) else 0;
    const maxnhar = max(dstnhar, srcnhar);
    const minnhar = min(dstnhar, srcnhar);

    if (!bothvoiced and voiced == src) {
        attach(dst, c.LLSM_FRAME_F0, toAny(c.llsm_create_fp(src_f0)), toDestructor(&c.llsm_delete_fp), toCopy(&c.llsm_copy_fp));
        attach(dst, c.LLSM_FRAME_RD, toAny(c.llsm_create_fp(src_rd_ptr.*)), toDestructor(&c.llsm_delete_fp), toCopy(&c.llsm_copy_fp));
    } else if (voiced == null) {
        attach(dst, c.LLSM_FRAME_F0, toAny(c.llsm_create_fp(0)), toDestructor(&c.llsm_delete_fp), toCopy(&c.llsm_copy_fp));
        attach(dst, c.LLSM_FRAME_RD, toAny(c.llsm_create_fp(1.0)), toDestructor(&c.llsm_delete_fp), toCopy(&c.llsm_copy_fp));
    }

    const nspec: c_int = if (dst_vtmagn_ptr) |p| c.llsm_fparray_length(p) else if (src_vtmagn_ptr) |p| c.llsm_fparray_length(p) else 0;

    if (bothvoiced) {
        attach(dst, c.LLSM_FRAME_F0, toAny(c.llsm_create_fp(linterp(dst_f0, src_f0, ratio))), toDestructor(&c.llsm_delete_fp), toCopy(&c.llsm_copy_fp));
        attach(dst, c.LLSM_FRAME_RD, toAny(c.llsm_create_fp(linterp(dst_rd_ptr.* , src_rd_ptr.* , ratio))), toDestructor(&c.llsm_delete_fp), toCopy(&c.llsm_copy_fp));

        const vsphse = c.llsm_create_fparray(maxnhar);
        const vtmagn = c.llsm_create_fparray(nspec);

        var i: c_int = 0;
        while (i < minnhar) : (i += 1) {
            const idx = @as(usize, @intCast(i));
            vsphse[idx] = linterpc(dst_vsphse_ptr.?[idx], src_vsphse_ptr.?[idx], ratio);
        }
        var j: c_int = 0;
        while (j < nspec) : (j += 1) {
            const idx = @as(usize, @intCast(j));
            vtmagn[idx] = linterp(dst_vtmagn_ptr.?[idx], src_vtmagn_ptr.?[idx], ratio);
        }
        if (dstnhar < srcnhar) {
            var k: c_int = minnhar;
            while (k < maxnhar) : (k += 1) {
                const idx = @as(usize, @intCast(k));
                vsphse[idx] = src_vsphse_ptr.?[idx];
            }
        }

        attach(dst, c.LLSM_FRAME_VSPHSE, toAny(vsphse), toDestructor(&c.llsm_delete_fparray), toCopy(&c.llsm_copy_fparray));
        attach(dst, c.LLSM_FRAME_VTMAGN, toAny(vtmagn), toDestructor(&c.llsm_delete_fparray), toCopy(&c.llsm_copy_fparray));
    } else if (voiced == src) {
        const vsphse = c.llsm_copy_fparray(src_vsphse_ptr.?);
        const vtmagn = c.llsm_copy_fparray(src_vtmagn_ptr.?);
        attach(dst, c.LLSM_FRAME_VSPHSE, toAny(vsphse), toDestructor(&c.llsm_delete_fparray), toCopy(&c.llsm_copy_fparray));
        attach(dst, c.LLSM_FRAME_VTMAGN, toAny(vtmagn), toDestructor(&c.llsm_delete_fparray), toCopy(&c.llsm_copy_fparray));
        const fade = mag2db(max(EPS, ratio));
        var i: c_int = 0;
        while (i < nspec) : (i += 1) {
            vtmagn[@as(usize, @intCast(i))] += fade;
        }
    } else {
        if (dst_vtmagn_ptr) |vtmagn| {
            const fade = mag2db(max(EPS, 1.0 - ratio));
            var i: c_int = 0;
            while (i < nspec) : (i += 1) {
                vtmagn[@as(usize, @intCast(i))] += fade;
            }
        }
    }

    if (dst_vtmagn_ptr) |vtmagn| {
        var i: c_int = 0;
        while (i < nspec) : (i += 1) {
            const idx = @as(usize, @intCast(i));
            vtmagn[idx] = max(@as(FP, -80), vtmagn[idx]);
        }
    }

    interp_nmframe(dst_nm, src_nm, ratio, dst_f0 > 0, src_f0 > 0);
}

fn base64decoderForUtau(x: u8, y: u8) i32 {
    var ans1: i32 = 0;
    var ans2: i32 = 0;

    if (x == '+') ans1 = 62;
    if (x == '/') ans1 = 63;
    if (x >= '0' and x <= '9') ans1 = @as(i32, x) + 4;
    if (x >= 'A' and x <= 'Z') ans1 = @as(i32, x) - 65;
    if (x >= 'a' and x <= 'z') ans1 = @as(i32, x) - 71;

    if (y == '+') ans2 = 62;
    if (y == '/') ans2 = 63;
    if (y >= '0' and y <= '9') ans2 = @as(i32, y) + 4;
    if (y >= 'A' and y <= 'Z') ans2 = @as(i32, y) - 65;
    if (y >= 'a' and y <= 'z') ans2 = @as(i32, y) - 71;

    var ans = (ans1 << 6) | ans2;
    if (ans >= 2048) ans -= 4096;
    return ans;
}

fn getF0Contour(input: []const u8, output: []f64) usize {
    var i: usize = 0;
    var count: usize = 0;
    var tmp: f64 = 0.0;

    while (i < input.len) {
        if (input[i] == '#') {
            var length: usize = 0;
            var j = i + 1;
            while (j < input.len and input[j] != '#') : (j += 1) {
                length = length * 10 + (input[j] - '0');
            }
            i = j + 1;
            var k: usize = 0;
            while (k < length and count < output.len) : (k += 1) {
                output[count] = tmp;
                count += 1;
            }
        } else {
            if (count < output.len and i + 1 < input.len) {
                tmp = @as(f64, @floatFromInt(base64decoderForUtau(input[i], input[i + 1])));
                output[count] = tmp;
                count += 1;
            }
            i += 2;
        }
    }

    return count;
}

fn getFreqAvg(f0: []const f64) f64 {
    var freq_avg: f64 = 0;
    var base_value: f64 = 0;
    var i: usize = 0;
    while (i < f0.len) : (i += 1) {
        const value = f0[i];
        if (value < 1000.0 and value > 55.0) {
            var r: f64 = 1.0;
            var p: [6]f64 = undefined;
            var j: usize = 0;
            while (j <= 5) : (j += 1) {
                if (i > j) {
                    const q = f0[i - j - 1] - value;
                    p[j] = value / (value + q * q);
                } else {
                    p[j] = 1 / (1 + value);
                }
                r *= p[j];
            }
            freq_avg += value * r;
            base_value += r;
        }
    }
    if (base_value > 0) {
        freq_avg /= base_value;
    }
    return freq_avg;
}

fn parse_note_to_midi(note_str: []const u8) i32 {
    if (note_str.len == 0) return -1;
    var base_note: i32 = -1;
    switch (std.ascii.toUpper(note_str[0])) {
        'C' => base_note = 0,
        'D' => base_note = 2,
        'E' => base_note = 4,
        'F' => base_note = 5,
        'G' => base_note = 7,
        'A' => base_note = 9,
        'B' => base_note = 11,
        else => return -1,
    }

    var offset: usize = 1;
    if (offset < note_str.len and note_str[offset] == '#') {
        base_note += 1;
        offset += 1;
    } else if (offset < note_str.len and note_str[offset] == 'b') {
        base_note -= 1;
        offset += 1;
    }

    const octave = std.fmt.parseInt(i32, note_str[offset..], 10) catch return -1;
    return (octave + 1) * 12 + base_note;
}

fn note_to_frequency(note_str: []const u8) f32 {
    const midi = parse_note_to_midi(note_str);
    if (midi < 0) return -1.0;
    return @as(f32, @floatCast(440.0 * std.math.pow(f64, 2.0, (@as(f64, @floatFromInt(midi)) - 69.0) / 12.0)));
}

fn convert_cents_to_hz_offset(cents: []const f64, nfrm: usize, nhop: i32, fs: i32, tempo: f32, out_ratio_offset: []f32) void {
    const frame_duration_sec = @as(f32, @floatFromInt(nhop)) / @as(f32, @floatFromInt(fs));
    const pit_interval_sec = (60.0 / 96.0) / tempo;

    var i: usize = 0;
    while (i < nfrm) : (i += 1) {
        const time_sec = @as(f32, @floatFromInt(i)) * frame_duration_sec;
        const idx = time_sec / pit_interval_sec;
        var idx0 = @as(isize, @intFromFloat(idx));
        if (idx0 < 0) idx0 = 0;
        if (idx0 >= @as(isize, @intCast(cents.len))) idx0 = @as(isize, @intCast(cents.len - 1));
        var idx1 = idx0 + 1;
        if (idx1 >= @as(isize, @intCast(cents.len))) idx1 = @as(isize, @intCast(cents.len - 1));
        const frac = idx - @as(f32, @floatFromInt(idx0));
        const cents_interp = @as(f32, @floatCast(cents[@as(usize, @intCast(idx0))] * (1.0 - @as(f64, frac)) + cents[@as(usize, @intCast(idx1))] * @as(f64, frac)));
        const ratio = @as(f32, @floatCast(std.math.pow(f64, 2.0, @as(f64, cents_interp) / 1200.0)));
        out_ratio_offset[i] = ratio - 1.0;
    }
}

fn apply_velocity(chunk: *c.llsm_chunk, velocity: f32, consonant_frames: *i32, total_frames: i32) void {
    const consonant_frames_old = consonant_frames.*;
    if (total_frames <= consonant_frames_old + 1) {
        std.debug.print("main_resampler: error applying velocity, no velocity applied.\n", .{});
        return;
    }

    var consonant_frames_new = @as(i32, @intFromFloat(@as(f32, @floatFromInt(consonant_frames_old)) * velocity + 0.5));
    if (consonant_frames_new < 1) consonant_frames_new = 1;
    if (consonant_frames_new > total_frames - 1) consonant_frames_new = total_frames - 1;
    consonant_frames.* = consonant_frames_new;

    const tmp = c.llsm_create_chunk(chunk.*.conf, consonant_frames_new);

    var i: i32 = 0;
    while (i < consonant_frames_new) : (i += 1) {
        const mapped = @as(FP, @floatFromInt(i)) * @as(FP, @floatFromInt(consonant_frames_old)) / @as(FP, @floatFromInt(consonant_frames_new));
        var base = @as(i32, @intFromFloat(mapped));
        const ratio = mapped - @as(FP, @floatFromInt(base));

        base = min(base, consonant_frames_old - 2);
        if (base < 0) base = 0;

        tmp.*.frames[@as(usize, @intCast(i))] = c.llsm_copy_container(chunk.*.frames[@as(usize, @intCast(base))]);
        interp_llsm_frame(tmp.*.frames[@as(usize, @intCast(i))], chunk.*.frames[@as(usize, @intCast(base + 1))], ratio);

        const resvec = alignedManyPtr(FP, c.llsm_container_get(chunk.*.frames[@as(usize, @intCast(base))], c.LLSM_FRAME_PSDRES));
        if (resvec) |vec| {
            attach(tmp.*.frames[@as(usize, @intCast(i))], c.LLSM_FRAME_PSDRES, toAny(c.llsm_copy_fparray(vec)), toDestructor(&c.llsm_delete_fparray), toCopy(&c.llsm_copy_fparray));
        }
    }

    i = 0;
    while (i < consonant_frames_new) : (i += 1) {
        if (chunk.*.frames[@as(usize, @intCast(i))]) |frame| {
            c.llsm_delete_container(frame);
        }
        chunk.*.frames[@as(usize, @intCast(i))] = c.llsm_copy_container(tmp.*.frames[@as(usize, @intCast(i))]);
    }

    const vowel_frames_old = total_frames - consonant_frames_old;
    const vowel_frames_new = total_frames - consonant_frames_new;

    var v: i32 = 0;
    while (v < vowel_frames_new) : (v += 1) {
        const dst_idx = consonant_frames_new + v;
        var old_idx = consonant_frames_old + @as(i32, @intFromFloat(@as(f32, @floatFromInt(v)) * (@as(f32, @floatFromInt(vowel_frames_old)) / @as(f32, @floatFromInt(vowel_frames_new)))));
        if (old_idx >= total_frames) old_idx = total_frames - 1;

        const src = chunk.*.frames[@as(usize, @intCast(old_idx))];
        const new_frame = c.llsm_copy_container(src);

        if (chunk.*.frames[@as(usize, @intCast(dst_idx))]) |frame| {
            c.llsm_delete_container(frame);
        }
        chunk.*.frames[@as(usize, @intCast(dst_idx))] = new_frame;
    }

    var tail: i32 = consonant_frames_new + vowel_frames_new;
    while (tail < total_frames) : (tail += 1) {
        if (chunk.*.frames[@as(usize, @intCast(tail))]) |frame| {
            c.llsm_delete_container(frame);
        }
        chunk.*.frames[@as(usize, @intCast(tail))] = c.llsm_create_frame(0, 0, 0, 0);
    }

    c.llsm_delete_chunk(tmp);
}

fn apply_tension(chunk: *c.llsm_chunk, tension: FP) void {
    const nfrm_ptr = alignedPtr(c_int, c.llsm_container_get(chunk.*.conf, c.LLSM_CONF_NFRM)) orelse return;

    const t = tension / 100.0;
    const slope_db: FP = 32.0 * t;
    const pivot: FP = 0.25;
    const alpha: FP = 2.6;
    const eps: FP = 1e-12;

    var i: c_int = 0;
    while (i < nfrm_ptr.*) : (i += 1) {
        const hm = alignedPtr(c.llsm_hmframe, c.llsm_container_get(chunk.*.frames[@as(usize, @intCast(i))], c.LLSM_FRAME_HM)) orelse continue;
        if (hm.*.ampl == null or hm.*.nhar <= 0) continue;

        var sum0: FP = 0;
        var j: c_int = 0;
        while (j < hm.*.nhar) : (j += 1) {
            sum0 += hm.*.ampl[@as(usize, @intCast(j))];
        }

        j = 0;
        while (j < hm.*.nhar) : (j += 1) {
            const w: FP = if (hm.*.nhar > 1) @as(FP, @floatFromInt(j)) / @as(FP, @floatFromInt(hm.*.nhar - 1)) else 0;
            const w_eased: FP = 0.5 - 0.5 * @as(FP, @floatCast(std.math.cos(@as(f64, std.math.pi) * @as(f64, w))));
            const h = @as(FP, @floatCast(std.math.tanh(@as(f64, alpha) * (@as(f64, w_eased) - @as(f64, pivot)))));
            const g_db = slope_db * h;
            const a = hm.*.ampl[@as(usize, @intCast(j))];
            var adb = 20.0 * @as(FP, @floatCast(std.math.log10(@as(f64, a + eps))));
            adb += g_db;
            var anew = @as(FP, @floatCast(std.math.pow(f64, 10.0, @as(f64, adb) / 20.0)));
            if (anew > 1.0) anew = 1.0;
            if (anew < 0.0) anew = 0.0;
            hm.*.ampl[@as(usize, @intCast(j))] = anew;
        }

        var sum1: FP = 0;
        j = 0;
        while (j < hm.*.nhar) : (j += 1) {
            sum1 += hm.*.ampl[@as(usize, @intCast(j))];
        }
        if (sum0 > 0 and sum1 > 0) {
            const k = sum0 / sum1;
            j = 0;
            while (j < hm.*.nhar) : (j += 1) {
                const v = hm.*.ampl[@as(usize, @intCast(j))] * k;
                hm.*.ampl[@as(usize, @intCast(j))] = if (v > 1.0) 1.0 else v;
            }
        }
    }
}

const Flags = struct {
    Mt: i32 = 0,
    t: i32 = 0,
    g: i32 = 0,
    P: i32 = 0,
    e: i32 = 0,
};

fn clamp_int(val: i32, lo: i32, hi: i32) i32 {
    return if (val < lo) lo else if (val > hi) hi else val;
}

fn parse_flag_string(str: []const u8) Flags {
    var flags = Flags{};
    var i: usize = 0;
    while (i < str.len) {
        if (i + 1 < str.len and str[i] == 'M' and str[i + 1] == 't') {
            i += 2;
            const start = i;
            while (i < str.len and (str[i] == '-' or std.ascii.isDigit(str[i]))) : (i += 1) {}
            flags.Mt = std.fmt.parseInt(i32, str[start..i], 10) catch 0;
            flags.Mt = clamp_int(flags.Mt, -100, 100);
        } else if (str[i] == 't') {
            i += 1;
            const start = i;
            while (i < str.len and (str[i] == '-' or std.ascii.isDigit(str[i]))) : (i += 1) {}
            flags.t = std.fmt.parseInt(i32, str[start..i], 10) catch 0;
            flags.t = clamp_int(flags.t, -9, 9);
        } else if (str[i] == 'g') {
            i += 1;
            const start = i;
            while (i < str.len and (str[i] == '-' or std.ascii.isDigit(str[i]))) : (i += 1) {}
            flags.g = std.fmt.parseInt(i32, str[start..i], 10) catch 0;
            flags.g = clamp_int(flags.g, -100, 100);
        } else if (str[i] == 'P') {
            i += 1;
            const start = i;
            while (i < str.len and (str[i] == '-' or std.ascii.isDigit(str[i]))) : (i += 1) {}
            flags.P = std.fmt.parseInt(i32, str[start..i], 10) catch 0;
            flags.P = clamp_int(flags.P, 0, 100);
        } else if (str[i] == 'e') {
            i += 1;
            flags.e = 1;
        } else {
            i += 1;
        }
    }
    return flags;
}

fn normalize_waveform(waveform: [*]FP, length: i32, target_peak: FP, P_flag: i32) void {
    if (P_flag <= 0) return;

    var peak: FP = 0.0;
    var i: i32 = 0;
    while (i < length) : (i += 1) {
        const abs_val = @abs(waveform[@as(usize, @intCast(i))]);
        if (abs_val > peak) peak = abs_val;
    }
    if (peak < 1e-9) return;

    const full_scale = target_peak / peak;
    const blend = @as(FP, @floatFromInt(P_flag)) / 100.0;
    const scale = linterp(1.0, full_scale, blend);

    i = 0;
    while (i < length) : (i += 1) {
        waveform[@as(usize, @intCast(i))] *= scale;
    }
}

fn parse_tempo(tempo_str: []const u8) i32 {
    var slice = tempo_str;
    if (slice.len > 0 and slice[0] == '!') slice = slice[1..];
    return std.fmt.parseInt(i32, slice, 10) catch 0;
}

const ResamplerData = struct {
    input: [*:0]const u8,
    output: [*:0]const u8,
    tone: f32,
    velocity: f32,
    flags: []const u8,
    offset: f32,
    length: f32,
    consonant: f32,
    cutoff: f32,
    volume: i32,
    modulation: i32,
    tempo: i32,
    pitch_curve: []const u8,
};

fn resample(allocator: std.mem.Allocator, data: ResamplerData) !i32 {
    var f0_curve = try allocator.alloc(f64, 3000);
    defer allocator.free(f0_curve);
    const pit_len = getF0Contour(data.pitch_curve, f0_curve);
    if (pit_len == 0) return 1;

    const velocity = @as(f32, @floatCast(std.math.exp2(1.0 - data.velocity / 100.0)));
    const flags = parse_flag_string(data.flags);

    const input_slice = std.mem.span(data.input);
    const base_idx = std.mem.lastIndexOfScalar(u8, input_slice, '.') orelse input_slice.len;
    const llsm_path = try std.fmt.allocPrintZ(allocator, "{s}.llsm2", .{input_slice[0..base_idx]});
    defer allocator.free(llsm_path);

    const llsm_file = c.fopen(llsm_path, "rb");

    const opt_a = c.llsm_create_aoptions();
    var chunk: ?*c.llsm_chunk = null;
    const nhop: c_int = 128;
    var fs: c_int = 0;
    var nbit: c_int = 0;
    var nx: c_int = 0;
    var input: ?[*]FP = null;
    var f0: ?[*]FP = null;
    var nfrm: c_int = 0;

    if (llsm_file) |file| {
        _ = c.fclose(file);
        std.debug.print("Loading cached LLSM analysis: {s}\n", .{llsm_path});
        chunk = read_llsm(llsm_path, &nfrm, &fs, &nbit);
        if (chunk == null) {
            std.debug.print("Failed to read .llsm2 file\n", .{});
            c.llsm_delete_aoptions(opt_a);
            return 1;
        }
    } else {
        std.debug.print("Reading input WAV: {s}\n", .{data.input});
        input = c.wavread(@constCast(data.input), &fs, &nbit, &nx);
        if (input == null) {
            c.llsm_delete_aoptions(opt_a);
            return 1;
        }

        std.debug.print("Estimating F0\n", .{});
        var param = c.pyin_init(nhop);
        param.fmin = 50.0;
        param.fmax = 800.0;
        param.trange = 24;
        param.bias = 2;
        param.nf = @as(c_int, @intFromFloat(@ceil(@as(f32, @floatFromInt(fs)) * 0.025)));
        f0 = c.pyin_analyze(param, input.?, nx, @as(FP, @floatFromInt(fs)), &nfrm);
        if (f0 == null) {
            c.free(input.?);
            c.llsm_delete_aoptions(opt_a);
            return 1;
        }

        opt_a.*.thop = @as(FP, @floatFromInt(nhop)) / @as(FP, @floatFromInt(fs));
        opt_a.*.f0_refine = 1;
        opt_a.*.hm_method = c.LLSM_AOPTION_HMCZT;

        std.debug.print("Analysis\n", .{});
        chunk = c.llsm_analyze(opt_a, input.?, nx, @as(FP, @floatFromInt(fs)), f0.?, nfrm, null);
        if (chunk == null) {
            c.free(input.?);
            c.free(f0.?);
            c.llsm_delete_aoptions(opt_a);
            return 1;
        }

        std.debug.print("Saving analysis result to cache: {s}\n", .{llsm_path});
        if (save_llsm(chunk.?, llsm_path, opt_a, &fs, &nbit) != 0) {
            std.debug.print("Failed to save .llsm2 file.\n", .{});
        }

        c.free(input.?);
        c.free(f0.?);
    }

    const opt_s = c.llsm_create_soptions(@as(FP, @floatFromInt(fs)));

    std.debug.print("Phase sync/stretching\n", .{});

    var start_frame = @as(i32, @intFromFloat(@round((data.offset / 1000.0) * @as(f32, @floatFromInt(fs)) / @as(f32, @floatFromInt(nhop)))));
    var end_frame: i32 = 0;
    if (data.cutoff < 0) {
        end_frame = @as(i32, @intFromFloat(@round(((data.offset + @abs(data.cutoff)) / 1000.0) * @as(f32, @floatFromInt(fs)) / @as(f32, @floatFromInt(nhop)))));
    } else {
        end_frame = nfrm - @as(i32, @intFromFloat(@round((data.cutoff / 1000.0) * @as(f32, @floatFromInt(fs)) / @as(f32, @floatFromInt(nhop)))));
    }

    if (start_frame < 0) start_frame = 0;
    if (end_frame > nfrm) end_frame = nfrm;
    if (end_frame <= start_frame) end_frame = start_frame + 1;

    var consonant_frames = @as(i32, @intFromFloat(@round((data.consonant / 1000.0) * @as(f32, @floatFromInt(fs)) / @as(f32, @floatFromInt(nhop)))));
    if (consonant_frames > end_frame - start_frame) {
        consonant_frames = end_frame - start_frame;
    }
    const sample_frames = end_frame - start_frame;

    var total_frames = @as(i32, @intFromFloat(@round((data.length / 1000.0) * @as(f32, @floatFromInt(fs)) / @as(f32, @floatFromInt(nhop)))));
    if (total_frames < consonant_frames) {
        total_frames = consonant_frames + 1;
    }

    var f0_array = try allocator.alloc(f32, @as(usize, @intCast(total_frames)));
    defer allocator.free(f0_array);

    convert_cents_to_hz_offset(f0_curve[0..pit_len], @as(usize, @intCast(total_frames)), nhop, fs, @as(f32, @floatFromInt(data.tempo)), f0_array);

    const t_ratio = std.math.pow(f64, 2.0, @as(f64, @floatFromInt(flags.t)) / 120.0);
    var i: i32 = 0;
    while (i < total_frames) : (i += 1) {
        f0_array[@as(usize, @intCast(i))] = (@as(f32, @floatCast(1.0 + f0_array[@as(usize, @intCast(i))])) * @as(f32, @floatCast(t_ratio))) - 1.0;
    }

    const conf_new = c.llsm_copy_container(chunk.?.*.conf);
    attach(conf_new, c.LLSM_CONF_NFRM, toAny(c.llsm_create_int(total_frames)), toDestructor(&c.llsm_delete_int), toCopy(&c.llsm_copy_int));
    const chunk_new = c.llsm_create_chunk(conf_new, 1);
    c.llsm_delete_container(conf_new);

    var no_stretch: i32 = 0;

    if (total_frames <= sample_frames) {
        i = 0;
        while (i < total_frames) : (i += 1) {
            chunk_new.*.frames[@as(usize, @intCast(i))] = c.llsm_copy_container(chunk.?.*.frames[@as(usize, @intCast(start_frame + i))]);
        }
        no_stretch = 1;
    } else {
        i = 0;
        while (i < sample_frames) : (i += 1) {
            chunk_new.*.frames[@as(usize, @intCast(i))] = c.llsm_copy_container(chunk.?.*.frames[@as(usize, @intCast(start_frame + i))]);
        }
    }

    c.llsm_chunk_tolayer1(chunk_new, 2048);
    c.llsm_chunk_phasepropagate(chunk_new, -1);
    std.debug.print("nfrm: {d}\n", .{total_frames});

    var frames_for_velocity = sample_frames;
    if (frames_for_velocity > total_frames) frames_for_velocity = total_frames;

    if (data.velocity != 100.0) {
        apply_velocity(chunk_new, velocity, &consonant_frames, frames_for_velocity);
    }

    const vowel_sample_frames = sample_frames - consonant_frames;
    const vowel_total_frames = total_frames - consonant_frames;

    if (vowel_sample_frames <= 0 or vowel_total_frames <= 0 or vowel_sample_frames >= vowel_total_frames) {
        no_stretch = 1;
    } else {
        no_stretch = 0;
    }

    if (no_stretch == 0) {
        i = consonant_frames;
        while (i < total_frames) : (i += 1) {
            const mapped = @as(FP, @floatFromInt(i - consonant_frames)) * @as(FP, @floatFromInt(vowel_sample_frames)) / @as(FP, @floatFromInt(vowel_total_frames));
            var base = consonant_frames + @as(i32, @intFromFloat(mapped));
            const ratio = mapped - @as(FP, @floatFromInt(@as(i32, @intFromFloat(mapped))));
            base = min(base, consonant_frames + vowel_sample_frames - 2);
            if (base < consonant_frames) base = consonant_frames;

            const new_frame = c.llsm_copy_container(chunk_new.*.frames[@as(usize, @intCast(base))]);
            interp_llsm_frame(new_frame, chunk_new.*.frames[@as(usize, @intCast(base + 1))], ratio);

            var res_interp: ?[*]FP = null;
            const resvec = alignedManyPtr(FP, c.llsm_container_get(chunk_new.*.frames[@as(usize, @intCast(base))], c.LLSM_FRAME_PSDRES));
            if (resvec) |vec| {
                const next = min(base + 1, consonant_frames + vowel_sample_frames - 1);
                const resvec2 = alignedManyPtr(FP, c.llsm_container_get(chunk_new.*.frames[@as(usize, @intCast(next))], c.LLSM_FRAME_PSDRES));
                const rlen = c.llsm_fparray_length(vec);
                res_interp = c.llsm_create_fparray(rlen);
                var j: c_int = 0;
                while (j < rlen) : (j += 1) {
                    res_interp.?[@as(usize, @intCast(j))] = linterp(vec[@as(usize, @intCast(j))], if (resvec2) |vec2| vec2[@as(usize, @intCast(j))] else vec[@as(usize, @intCast(j))], ratio);
                }
            }

            if (chunk_new.*.frames[@as(usize, @intCast(i))]) |frame| {
                c.llsm_delete_container(frame);
            }

            chunk_new.*.frames[@as(usize, @intCast(i))] = new_frame;
            if (res_interp) |interp| {
                attach(chunk_new.*.frames[@as(usize, @intCast(i))], c.LLSM_FRAME_PSDRES, toAny(interp), toDestructor(&c.llsm_delete_fparray), toCopy(&c.llsm_copy_fparray));
            }
        }
    }

    {
        const xfade_frames: i32 = 4;
        const boundary = consonant_frames;
        var xf_start = boundary - xfade_frames;
        var xf_end = boundary + xfade_frames;
        if (xf_start < 0) xf_start = 0;
        if (xf_end >= total_frames) xf_end = total_frames - 1;

        i = xf_start;
        while (i <= xf_end) : (i += 1) {
            if (i <= 0 or i >= total_frames - 1) continue;
            const alpha: FP = 0.25;
            interp_llsm_frame(chunk_new.*.frames[@as(usize, @intCast(i))], chunk_new.*.frames[@as(usize, @intCast(i + 1))], alpha);
        }
    }

    const avg_len = min(sample_frames, total_frames);
    var f0_for_avg = try allocator.alloc(f64, @as(usize, @intCast(avg_len)));
    defer allocator.free(f0_for_avg);
    i = 0;
    while (i < avg_len) : (i += 1) {
        const f0_i = alignedPtr(FP, c.llsm_container_get(chunk_new.*.frames[@as(usize, @intCast(i))], c.LLSM_FRAME_F0));
        f0_for_avg[@as(usize, @intCast(i))] = if (f0_i) |ptr| ptr.* else 0.0;
    }
    var avg_f0_of_sample = getFreqAvg(f0_for_avg);
    if (avg_f0_of_sample < 50.0) avg_f0_of_sample = data.tone;
    const mod = @as(FP, @floatFromInt(data.modulation)) / 100.0;

    std.debug.print("nfrm: {d}\n", .{total_frames});

    i = 0;
    while (i < total_frames) : (i += 1) {
        attach(chunk_new.*.frames[@as(usize, @intCast(i))], c.LLSM_FRAME_HM, null, null, null);
        const f0_i = alignedPtr(FP, c.llsm_container_get(chunk_new.*.frames[@as(usize, @intCast(i))], c.LLSM_FRAME_F0)) orelse continue;
        const old_f0 = f0_i.*;
        if (old_f0 == 0.0) continue;

        const target = data.tone * (1.0 + f0_array[@as(usize, @intCast(i))]);
        const orig_ratio = if (avg_f0_of_sample > 0) old_f0 / @as(FP, @floatCast(avg_f0_of_sample)) else 1.0;
        const modulated_f0 = target * @as(FP, @floatCast(std.math.pow(f64, @as(f64, orig_ratio), @as(f64, mod))));

        var new_f0 = modulated_f0;
        if (new_f0 < 20.0) new_f0 = 20.0;
        f0_i.* = new_f0;

        const vt_magn = alignedManyPtr(FP, c.llsm_container_get(chunk_new.*.frames[@as(usize, @intCast(i))], c.LLSM_FRAME_VTMAGN));
        if (vt_magn) |magn| {
            const nspec = c.llsm_fparray_length(magn);
            const energy_comp = -20.0 * @as(FP, @floatCast(std.math.log10(@as(f64, new_f0 / old_f0))));
            var j: c_int = 0;
            while (j < nspec) : (j += 1) {
                magn[@as(usize, @intCast(j))] += energy_comp;
            }
        }
    }

    c.llsm_chunk_phasepropagate(chunk_new, 1);
    c.llsm_chunk_tolayer0(chunk_new);
    apply_tension(chunk_new, @as(FP, @floatFromInt(flags.Mt)));
    std.debug.print("Synthesis\n", .{});

    const out = c.llsm_synthesize(opt_s, chunk_new);
    if (out == null or out.*.y == null) {
        std.debug.print("Failed to synthesize output\n", .{});
        c.llsm_delete_chunk(chunk.?);
        c.llsm_delete_chunk(chunk_new);
        c.llsm_delete_aoptions(opt_a);
        c.llsm_delete_soptions(opt_s);
        return 1;
    }

    normalize_waveform(out.*.y, out.*.ny, 0.60, flags.P);

    const scale = @as(FP, @floatFromInt(data.volume)) / 100.0;
    i = 0;
    while (i < out.*.ny) : (i += 1) {
        out.*.y[@as(usize, @intCast(i))] *= scale;
    }

    c.wavwrite(out.*.y, out.*.ny, fs, nbit, @constCast(data.output));

    c.llsm_delete_output(out);
    c.llsm_delete_chunk(chunk.?);
    c.llsm_delete_chunk(chunk_new);
    c.llsm_delete_aoptions(opt_a);
    c.llsm_delete_soptions(opt_s);

    return 0;
}

pub fn main() !void {
    std.debug.print("moresampler2 version {s}\n", .{version});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2) {
        std.debug.print("At the moment, autolabeling is not supported.\n", .{});
        return;
    }

    if (args.len < 2) {
        std.debug.print("Moresampler is meant to be used inside of UTAU or OpenUtau.\n", .{});
        std.process.exit(1);
    }

    if (args.len == 14) {
        const input = try allocator.dupeZ(u8, args[1]);
        defer allocator.free(input);
        const output = try allocator.dupeZ(u8, args[2]);
        defer allocator.free(output);

        const data = ResamplerData{
            .input = input,
            .output = output,
            .tone = note_to_frequency(args[3]),
            .velocity = std.fmt.parseFloat(f32, args[4]) catch 0,
            .flags = args[5],
            .offset = std.fmt.parseFloat(f32, args[6]) catch 0,
            .length = std.fmt.parseFloat(f32, args[7]) catch 0,
            .consonant = std.fmt.parseFloat(f32, args[8]) catch 0,
            .cutoff = std.fmt.parseFloat(f32, args[9]) catch 0,
            .volume = std.fmt.parseInt(i32, args[10], 10) catch 0,
            .modulation = std.fmt.parseInt(i32, args[11], 10) catch 0,
            .tempo = parse_tempo(args[12]),
            .pitch_curve = args[13],
        };

        const result = try resample(allocator, data);
        if (result != 0) {
            std.process.exit(@as(u8, @intCast(result)));
        }
        return;
    }

    std.debug.print("Invalid arguments. Expected 14 arguments, got {d}.\n", .{args.len});
}
