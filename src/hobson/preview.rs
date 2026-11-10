use std::{mem, ptr};

use winapi::{
    shared::{
        minwindef::{FALSE, LPARAM, TRUE},
        windef::{HBITMAP, HDC, HWND, RECT},
    },
    um::{
        wingdi::{
            BitBlt, CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDIBits,
            SelectObject, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS, SRCCOPY,
        },
        winuser::{
            EnumWindows, GetDC, GetSystemMetrics, GetWindowRect, GetWindowTextLengthW,
            GetWindowTextW, IsIconic, IsWindowVisible, PrintWindow, ReleaseDC, SM_CXSCREEN,
            SM_CYSCREEN,
        },
    },
};

struct TitleHit {
    titles: Vec<String>,
    query: String,
    hwnd: HWND,
}

pub fn primary_jpeg(max_width: u32) -> Option<Vec<u8>> {
    unsafe {
        let hdc = GetDC(ptr::null_mut());
        if hdc.is_null() {
            return None;
        }
        let width = GetSystemMetrics(SM_CXSCREEN);
        let height = GetSystemMetrics(SM_CYSCREEN);
        let jpeg = blit_jpeg(hdc, 0, 0, width, height, max_width);
        ReleaseDC(ptr::null_mut(), hdc);
        jpeg
    }
}

pub fn window_titles() -> Vec<String> {
    let mut hit = TitleHit {
        titles: Vec::new(),
        query: String::new(),
        hwnd: ptr::null_mut(),
    };
    unsafe {
        EnumWindows(Some(enum_window), &mut hit as *mut TitleHit as LPARAM);
    }
    hit.titles
}

pub fn window_jpeg(title: &str, max_width: u32) -> Option<Vec<u8>> {
    let mut hit = TitleHit {
        titles: Vec::new(),
        query: title.to_lowercase(),
        hwnd: ptr::null_mut(),
    };
    unsafe {
        EnumWindows(Some(enum_window), &mut hit as *mut TitleHit as LPARAM);
    }
    if hit.hwnd.is_null() {
        return None;
    }
    unsafe {
        let mut rect: RECT = mem::zeroed();
        if GetWindowRect(hit.hwnd, &mut rect) == FALSE {
            return None;
        }
        let width = rect.right - rect.left;
        let height = rect.bottom - rect.top;
        if width < 16 || height < 16 {
            return None;
        }
        let screen = GetDC(ptr::null_mut());
        if screen.is_null() {
            return None;
        }
        let mem = CreateCompatibleDC(screen);
        let bitmap = CreateCompatibleBitmap(screen, width, height);
        ReleaseDC(ptr::null_mut(), screen);
        if mem.is_null() || bitmap.is_null() {
            if !mem.is_null() {
                DeleteDC(mem);
            }
            if !bitmap.is_null() {
                DeleteObject(bitmap as _);
            }
            return None;
        }
        let old = SelectObject(mem, bitmap as _);
        let printed = PrintWindow(hit.hwnd, mem, 2);
        let jpeg = if printed == FALSE {
            None
        } else {
            dib_jpeg(mem, bitmap, width, height, max_width)
        };
        SelectObject(mem, old);
        DeleteObject(bitmap as _);
        DeleteDC(mem);
        jpeg
    }
}

unsafe extern "system" fn enum_window(hwnd: HWND, lparam: LPARAM) -> i32 {
    let hit = &mut *(lparam as *mut TitleHit);
    if IsWindowVisible(hwnd) == FALSE || IsIconic(hwnd) != FALSE {
        return TRUE;
    }
    let len = GetWindowTextLengthW(hwnd);
    if len <= 0 {
        return TRUE;
    }
    let mut buf = vec![0u16; len as usize + 1];
    let n = GetWindowTextW(hwnd, buf.as_mut_ptr(), buf.len() as _);
    if n <= 0 {
        return TRUE;
    }
    let title = String::from_utf16_lossy(&buf[..n as usize]);
    if title == "Helper has control" {
        return TRUE;
    }
    if hit.query.is_empty() {
        if hit.titles.len() < 30 {
            let short = title.chars().take(80).collect::<String>();
            if !hit.titles.iter().any(|have| have == &short) {
                hit.titles.push(short);
            }
        }
    } else if title.to_lowercase().contains(&hit.query) && hit.hwnd.is_null() {
        hit.hwnd = hwnd;
        return FALSE;
    }
    TRUE
}

unsafe fn blit_jpeg(screen: HDC, x: i32, y: i32, width: i32, height: i32, max_width: u32) -> Option<Vec<u8>> {
    if width < 16 || height < 16 {
        return None;
    }
    let mem = CreateCompatibleDC(screen);
    let bitmap = CreateCompatibleBitmap(screen, width, height);
    if mem.is_null() || bitmap.is_null() {
        if !mem.is_null() {
            DeleteDC(mem);
        }
        if !bitmap.is_null() {
            DeleteObject(bitmap as _);
        }
        return None;
    }
    let old = SelectObject(mem, bitmap as _);
    let copied = BitBlt(mem, 0, 0, width, height, screen, x, y, SRCCOPY);
    let jpeg = if copied == FALSE {
        None
    } else {
        dib_jpeg(mem, bitmap, width, height, max_width)
    };
    SelectObject(mem, old);
    DeleteObject(bitmap as _);
    DeleteDC(mem);
    jpeg
}

unsafe fn dib_jpeg(mem: HDC, bitmap: HBITMAP, width: i32, height: i32, max_width: u32) -> Option<Vec<u8>> {
    let mut info: BITMAPINFO = mem::zeroed();
    info.bmiHeader.biSize = mem::size_of::<BITMAPINFOHEADER>() as u32;
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    let mut bgra = vec![0u8; (width as usize) * (height as usize) * 4];
    let rows = GetDIBits(
        mem,
        bitmap,
        0,
        height as u32,
        bgra.as_mut_ptr() as _,
        &mut info,
        DIB_RGB_COLORS,
    );
    if rows == 0 {
        return None;
    }
    jpeg_from_bgra(width as u32, height as u32, &bgra, max_width)
}

fn jpeg_from_bgra(width: u32, height: u32, bgra: &[u8], max_width: u32) -> Option<Vec<u8>> {
    if width == 0 || height == 0 || max_width == 0 {
        return None;
    }
    let scale = if width > max_width {
        width as f32 / max_width as f32
    } else {
        1.0
    };
    let out_w = ((width as f32) / scale).max(1.0) as u32;
    let out_h = ((height as f32) / scale).max(1.0) as u32;
    let mut rgb = vec![0u8; (out_w as usize) * (out_h as usize) * 3];
    for y in 0..out_h {
        for x in 0..out_w {
            let sx = ((x as f32) * scale) as u32;
            let sy = ((y as f32) * scale) as u32;
            let sx = sx.min(width - 1) as usize;
            let sy = sy.min(height - 1) as usize;
            let i = (sy * width as usize + sx) * 4;
            if i + 2 >= bgra.len() {
                continue;
            }
            let o = ((y as usize) * (out_w as usize) + x as usize) * 3;
            rgb[o] = bgra[i + 2];
            rgb[o + 1] = bgra[i + 1];
            rgb[o + 2] = bgra[i];
        }
    }
    let mut encoded = Vec::new();
    let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut encoded, 40);
    encoder
        .encode(&rgb, out_w, out_h, image::ColorType::Rgb8)
        .ok()?;
    if encoded.len() > 60_000 {
        return None;
    }
    Some(encoded)
}
