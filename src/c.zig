///! C library bindings for libllsm, ciglet, libpyin, and libgvps.
///! These are thin wrappers that re-export the C types and functions
///! under Zig-friendly names while maintaining full compatibility.
const std = @import("std");

// Pull in all C headers with FP_TYPE=float defined
pub const raw = @cImport({
    @cDefine("FP_TYPE", "float");
    @cInclude("ciglet.h");
    @cInclude("llsm.h");
    @cInclude("pyin.h");
});

// Re-export common C types for ergonomic access
pub const FpType = raw.FP_TYPE;
pub const LlsmContainer = raw.llsm_container;
pub const LlsmChunk = raw.llsm_chunk;
pub const LlsmHmframe = raw.llsm_hmframe;
pub const LlsmNmframe = raw.llsm_nmframe;
pub const LlsmAoptions = raw.llsm_aoptions;
pub const LlsmSoptions = raw.llsm_soptions;
pub const LlsmOutput = raw.llsm_output;
pub const PyinConfig = raw.pyin_config;

// Frame index constants
pub const FRAME_F0 = raw.LLSM_FRAME_F0;
pub const FRAME_HM = raw.LLSM_FRAME_HM;
pub const FRAME_NM = raw.LLSM_FRAME_NM;
pub const FRAME_PSDRES = raw.LLSM_FRAME_PSDRES;
pub const FRAME_RD = raw.LLSM_FRAME_RD;
pub const FRAME_VTMAGN = raw.LLSM_FRAME_VTMAGN;
pub const FRAME_VSPHSE = raw.LLSM_FRAME_VSPHSE;

// Config index constants
pub const CONF_NFRM = raw.LLSM_CONF_NFRM;
pub const AOPTION_HMCZT = raw.LLSM_AOPTION_HMCZT;

// --- llsm functions ---

pub fn createAoptions() *LlsmAoptions {
    return raw.llsm_create_aoptions().?;
}

pub fn deleteAoptions(opt: *LlsmAoptions) void {
    raw.llsm_delete_aoptions(opt);
}

pub fn createSoptions(fs: FpType) *LlsmSoptions {
    return raw.llsm_create_soptions(fs).?;
}

pub fn deleteSoptions(opt: *LlsmSoptions) void {
    raw.llsm_delete_soptions(opt);
}

pub fn aoptionsToconf(src: *LlsmAoptions, fnyq: FpType) ?*LlsmContainer {
    return raw.llsm_aoptions_toconf(src, fnyq);
}

pub fn createFp(x: FpType) *FpType {
    return raw.llsm_create_fp(x).?;
}

pub fn createInt(x: c_int) *c_int {
    return raw.llsm_create_int(x).?;
}

pub fn createFparray(size: c_int) ?[*]FpType {
    return raw.llsm_create_fparray(size);
}

pub fn copyFp(src: *FpType) *FpType {
    return @as(*FpType, @ptrCast(raw.llsm_copy_fp(src).?));
}

pub fn copyInt(src: *c_int) *c_int {
    return @as(*c_int, @ptrCast(raw.llsm_copy_int(src).?));
}

pub fn copyFparray(src: [*]FpType) ?[*]FpType {
    return raw.llsm_copy_fparray(src);
}

pub fn deleteFparray(dst: [*]FpType) void {
    raw.llsm_delete_fparray(dst);
}

pub fn fparrayLength(src: [*]FpType) c_int {
    return raw.llsm_fparray_length(src);
}

pub fn createChunk(conf: *LlsmContainer, init_frames: c_int) ?*LlsmChunk {
    return raw.llsm_create_chunk(conf, init_frames);
}

pub fn copyContainer(src: *LlsmContainer) ?*LlsmContainer {
    return raw.llsm_copy_container(src);
}

pub fn deleteContainer(dst: *LlsmContainer) void {
    raw.llsm_delete_container(dst);
}

pub fn deleteChunk(dst: *LlsmChunk) void {
    raw.llsm_delete_chunk(dst);
}

pub fn containerGet(src: *LlsmContainer, index: c_int) ?*anyopaque {
    return raw.llsm_container_get(src, index);
}

pub fn containerAttach(
    dst: *LlsmContainer,
    index: c_int,
    ptr: ?*anyopaque,
    dtor: raw.llsm_fdestructor,
    copy_ctor: raw.llsm_fcopy,
) void {
    raw.llsm_container_attach_(dst, index, ptr, dtor, copy_ctor);
}

pub fn createFrame(nhar: c_int, nchannel: c_int, nhar_e: c_int, npsd: c_int) ?*LlsmContainer {
    return raw.llsm_create_frame(nhar, nchannel, nhar_e, npsd);
}

pub fn createHmframe(nhar: c_int) ?*LlsmHmframe {
    return raw.llsm_create_hmframe(nhar);
}

pub fn deleteHmframe(dst: ?*anyopaque) void {
    raw.llsm_delete_hmframe(@ptrCast(@alignCast(dst)));
}

pub fn copyHmframe(src: ?*anyopaque) ?*anyopaque {
    return @ptrCast(raw.llsm_copy_hmframe(@ptrCast(@alignCast(src))));
}

pub fn deleteNmframe(dst: ?*anyopaque) void {
    raw.llsm_delete_nmframe(@ptrCast(@alignCast(dst)));
}

pub fn copyNmframe(src: ?*anyopaque) ?*anyopaque {
    return @ptrCast(raw.llsm_copy_nmframe(@ptrCast(@alignCast(src))));
}

pub fn chunkTolayer1(dst: *LlsmChunk, nfft: c_int) void {
    raw.llsm_chunk_tolayer1(dst, nfft);
}

pub fn chunkTolayer0(dst: *LlsmChunk) void {
    raw.llsm_chunk_tolayer0(dst);
}

pub fn chunkPhasepropagate(dst: *LlsmChunk, sign: c_int) void {
    raw.llsm_chunk_phasepropagate(dst, sign);
}

pub fn analyze(
    options: *LlsmAoptions,
    x: [*]FpType,
    nx: c_int,
    fs: FpType,
    f0: [*]FpType,
    nfrm: c_int,
) ?*LlsmChunk {
    return raw.llsm_analyze(options, x, nx, fs, f0, nfrm, null);
}

pub fn synthesize(options: *LlsmSoptions, src: *LlsmChunk) ?*LlsmOutput {
    return raw.llsm_synthesize(options, src);
}

pub fn deleteOutput(dst: *LlsmOutput) void {
    raw.llsm_delete_output(dst);
}

// Function pointer casts for container_attach
pub fn deleteFpDtor() raw.llsm_fdestructor {
    return @ptrCast(&raw.llsm_delete_fp);
}

pub fn copyFpCtor() raw.llsm_fcopy {
    return @ptrCast(&raw.llsm_copy_fp);
}

pub fn deleteIntDtor() raw.llsm_fdestructor {
    return @ptrCast(&raw.llsm_delete_int);
}

pub fn copyIntCtor() raw.llsm_fcopy {
    return @ptrCast(&raw.llsm_copy_int);
}

pub fn deleteFparrayDtor() raw.llsm_fdestructor {
    return @ptrCast(&raw.llsm_delete_fparray);
}

pub fn copyFparrayCtor() raw.llsm_fcopy {
    return @ptrCast(&raw.llsm_copy_fparray);
}

pub fn freeDtor() raw.llsm_fdestructor {
    return @ptrCast(&raw.free);
}

// --- ciglet functions ---

pub fn wavread(filename: [*:0]const u8, fs: *c_int, nbit: *c_int, nx: *c_int) ?[*]FpType {
    return raw.wavread(@constCast(@ptrCast(filename)), fs, nbit, nx);
}

pub fn wavwrite(y: [*]FpType, ny: c_int, fs: c_int, nbit: c_int, filename: [*:0]const u8) void {
    raw.wavwrite(y, ny, fs, nbit, @constCast(@ptrCast(filename)));
}

/// Linear interpolation: a + (b - a) * ratio
pub inline fn linterp(a: FpType, b: FpType, ratio: FpType) FpType {
    return a + (b - a) * ratio;
}

// --- pyin functions ---

pub fn pyinInit(nhop: c_int) PyinConfig {
    return raw.pyin_init(nhop);
}

pub fn pyinAnalyze(param: PyinConfig, x: [*]FpType, nx: c_int, fs: FpType, nfrm: *c_int) ?[*]FpType {
    return raw.pyin_analyze(param, x, nx, fs, nfrm);
}

// --- C memory helpers ---

pub fn cFree(ptr: ?*anyopaque) void {
    raw.free(ptr);
}

pub fn cMalloc(comptime T: type, count: usize) ?[*]T {
    const ptr = raw.malloc(count * @sizeOf(T));
    if (ptr) |p| {
        return @ptrCast(@alignCast(p));
    }
    return null;
}

pub fn cRealloc(comptime T: type, old: ?[*]T, count: usize) ?[*]T {
    const ptr = raw.realloc(@ptrCast(old), count * @sizeOf(T));
    if (ptr) |p| {
        return @ptrCast(@alignCast(p));
    }
    return null;
}
