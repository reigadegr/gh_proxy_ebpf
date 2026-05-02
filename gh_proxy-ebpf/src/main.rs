#![no_std]
#![no_main]

use aya_ebpf::{bindings::TC_ACT_OK, macros::classifier, programs::TcContext};

use core::mem;

/// GitHub.com 的 IP 地址范围（需要根据实际情况更新）
const GITHUB_IPS: [(u32, u32); 4] = [
    (0x141C7000, 0xFFFFFF00), // 20.28.112.0/24
    (0x14CDF300, 0xFFFFFF00), // 20.205.243.0/24
    (0x8C520000, 0xFFFFF000), // 140.82.112.0/20
    (0xC01EFC00, 0xFFFFFC00), // 192.30.252.0/22
];

/// 本地代理 IP
const LOCAL_IP: u32 = 0x7F000001; // 127.0.0.1

/// 本地代理端口
const LOCAL_PORT: u16 = 443;

// 网络包头结构
#[repr(C)]
struct EthHdr {
    dst: [u8; 6],
    src: [u8; 6],
    ethertype: u16,
}

#[repr(C)]
struct Ipv4Hdr {
    version_ihl: u8,
    tos: u8,
    tot_len: u16,
    id: u16,
    frag_off: u16,
    ttl: u8,
    protocol: u8,
    check: u16,
    saddr: u32,
    daddr: u32,
}

#[repr(C)]
struct TcpHdr {
    source: u16,
    dest: u16,
    seq: u32,
    ack_seq: u32,
    doff_reserved: u8,
    flags: u8,
    window: u16,
    check: u16,
    urg_ptr: u16,
}

/// 出站流量处理（本地 -> GitHub）
#[classifier]
pub fn gh_proxy_egress(ctx: TcContext) -> i32 {
    match try_egress(&ctx) {
        Ok(ret) => ret,
        Err(_) => TC_ACT_OK,
    }
}

/// 入站流量处理（GitHub -> 本地）
#[classifier]
pub fn gh_proxy_ingress(ctx: TcContext) -> i32 {
    match try_ingress(&ctx) {
        Ok(ret) => ret,
        Err(_) => TC_ACT_OK,
    }
}

fn try_egress(ctx: &TcContext) -> Result<i32, i64> {
    let eth = unsafe { ptr_at_mut::<EthHdr>(ctx, 0)? };

    if u16::from_be(unsafe { (*eth).ethertype }) != 0x0800 {
        return Ok(TC_ACT_OK);
    }

    let ipv4 = unsafe { ptr_at_mut::<Ipv4Hdr>(ctx, mem::size_of::<EthHdr>())? };

    if unsafe { (*ipv4).protocol } != 6 {
        return Ok(TC_ACT_OK);
    }

    let tcp =
        unsafe { ptr_at_mut::<TcpHdr>(ctx, mem::size_of::<EthHdr>() + mem::size_of::<Ipv4Hdr>())? };

    let dst_ip = u32::from_be(unsafe { (*ipv4).daddr });
    let dst_port = u16::from_be(unsafe { (*tcp).dest });

    // 只处理目标是 GitHub 的 TCP 443 流量
    if dst_port == 443 && is_github_ip(dst_ip) {
        // 修改目标 IP 和端口
        unsafe {
            (*ipv4).daddr = u32::to_be(LOCAL_IP);
            (*tcp).dest = u16::to_be(LOCAL_PORT);
        }

        // 重新计算 IP 校验和
        unsafe {
            (*ipv4).check = 0;
            (*ipv4).check = calculate_checksum(ipv4 as *const _ as *const u8, 20);
        }

        // TCP 校验和需要重新计算（简化处理，设为 0）
        unsafe {
            (*tcp).check = 0;
        }
    }

    Ok(TC_ACT_OK)
}

fn try_ingress(ctx: &TcContext) -> Result<i32, i64> {
    let eth = unsafe { ptr_at_mut::<EthHdr>(ctx, 0)? };

    if u16::from_be(unsafe { (*eth).ethertype }) != 0x0800 {
        return Ok(TC_ACT_OK);
    }

    let ipv4 = unsafe { ptr_at_mut::<Ipv4Hdr>(ctx, mem::size_of::<EthHdr>())? };

    if unsafe { (*ipv4).protocol } != 6 {
        return Ok(TC_ACT_OK);
    }

    let tcp =
        unsafe { ptr_at_mut::<TcpHdr>(ctx, mem::size_of::<EthHdr>() + mem::size_of::<Ipv4Hdr>())? };

    let src_ip = u32::from_be(unsafe { (*ipv4).saddr });
    let src_port = u16::from_be(unsafe { (*tcp).source });

    // 来自本地代理的响应（日志已移除以兼容 Android 内核）

    Ok(TC_ACT_OK)
}

fn is_github_ip(ip: u32) -> bool {
    let ip_be = ip.to_be();

    for (network, mask) in GITHUB_IPS.iter() {
        if (ip_be & mask) == (*network & mask) {
            return true;
        }
    }

    false
}

#[inline(always)]
unsafe fn ptr_at_mut<T>(ctx: &TcContext, offset: usize) -> Result<*mut T, i64> {
    let start = ctx.data();
    let end = ctx.data_end();
    let len = mem::size_of::<T>();

    if start + offset + len > end {
        return Err(TC_ACT_OK.into());
    }

    Ok((start + offset) as *mut T)
}

// IP 校验和计算（使用有界循环以通过 BPF 验证器）
fn calculate_checksum(data: *const u8, len: usize) -> u16 {
    let mut sum: u32 = 0;

    // BPF 验证器要求有界循环，IP 头最多 15 个 16-bit word
    let words = len / 2;
    unsafe {
        if words > 0 {
            sum += u16::from_be(*(data as *const u16).add(0)) as u32;
        }
        if words > 1 {
            sum += u16::from_be(*(data as *const u16).add(1)) as u32;
        }
        if words > 2 {
            sum += u16::from_be(*(data as *const u16).add(2)) as u32;
        }
        if words > 3 {
            sum += u16::from_be(*(data as *const u16).add(3)) as u32;
        }
        if words > 4 {
            sum += u16::from_be(*(data as *const u16).add(4)) as u32;
        }
        if words > 5 {
            sum += u16::from_be(*(data as *const u16).add(5)) as u32;
        }
        if words > 6 {
            sum += u16::from_be(*(data as *const u16).add(6)) as u32;
        }
        if words > 7 {
            sum += u16::from_be(*(data as *const u16).add(7)) as u32;
        }
        if words > 8 {
            sum += u16::from_be(*(data as *const u16).add(8)) as u32;
        }
        if words > 9 {
            sum += u16::from_be(*(data as *const u16).add(9)) as u32;
        }
    }

    // 折叠进位（最多需要 2 次）
    sum = (sum & 0xFFFF) + (sum >> 16);
    sum = (sum & 0xFFFF) + (sum >> 16);

    !sum as u16
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    unsafe { core::hint::unreachable_unchecked() }
}
