use std::{
    ptr,
    sync::{
        atomic::{AtomicPtr, AtomicUsize, Ordering},
        Mutex,
    },
};

use winapi::{
    shared::{
        minwindef::{LPARAM, LRESULT, UINT, WPARAM},
        windef::HWND,
    },
    um::{
        wingdi::{CreateSolidBrush, DeleteObject, SetBkMode, SetTextColor, RGB, TRANSPARENT},
        libloaderapi::GetModuleHandleW,
        winuser::{
            BeginPaint, CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW,
            DrawTextW, EndPaint, FillRect, GetMessageW, GetSystemMetrics, PostMessageW,
            PostQuitMessage, RegisterClassW, SetLayeredWindowAttributes, SetWindowPos, ShowWindow,
            TranslateMessage, UpdateWindow, CS_HREDRAW, CS_VREDRAW, DT_CENTER, DT_SINGLELINE,
            DT_VCENTER, HWND_TOPMOST, LWA_ALPHA, SM_CXSCREEN, SWP_NOACTIVATE, SWP_NOMOVE,
            SWP_NOSIZE, SW_SHOWNOACTIVATE, WM_CLOSE, WM_DESTROY, WM_PAINT, WNDCLASSW,
            WS_EX_LAYERED, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_EX_TRANSPARENT,
            WS_POPUP,
        },
    },
};

static HWND_SLOT: AtomicPtr<winapi::ctypes::c_void> = AtomicPtr::new(ptr::null_mut());
static COUNT: AtomicUsize = AtomicUsize::new(0);
static LABEL: Mutex<String> = Mutex::new(String::new());

pub fn show(label: &str) {
    if let Ok(mut slot) = LABEL.lock() {
        *slot = format!("Helper has control · {label}");
    }
    if COUNT.fetch_add(1, Ordering::SeqCst) > 0 {
        return;
    }
    std::thread::spawn(banner_thread);
}

pub fn hide() {
    if COUNT.load(Ordering::SeqCst) == 0 {
        return;
    }
    if COUNT.fetch_sub(1, Ordering::SeqCst) != 1 {
        return;
    }
    let hwnd = HWND_SLOT.load(Ordering::SeqCst) as HWND;
    if !hwnd.is_null() {
        unsafe {
            PostMessageW(hwnd, WM_CLOSE, 0, 0);
        }
    }
}

fn banner_thread() {
    unsafe {
        let class_name = wide("HobsonHelperBanner");
        let instance = GetModuleHandleW(ptr::null());
        let mut wnd: WNDCLASSW = std::mem::zeroed();
        wnd.style = CS_HREDRAW | CS_VREDRAW;
        wnd.lpfnWndProc = Some(wnd_proc);
        wnd.hInstance = instance;
        wnd.lpszClassName = class_name.as_ptr();
        RegisterClassW(&wnd);
        let width = 460i32;
        let screen = GetSystemMetrics(SM_CXSCREEN);
        let hwnd = CreateWindowExW(
            WS_EX_TOPMOST
                | WS_EX_TOOLWINDOW
                | WS_EX_NOACTIVATE
                | WS_EX_LAYERED
                | WS_EX_TRANSPARENT,
            class_name.as_ptr(),
            wide("Helper has control").as_ptr(),
            WS_POPUP,
            (screen - width) / 2,
            12,
            width,
            32,
            ptr::null_mut(),
            ptr::null_mut(),
            instance,
            ptr::null_mut(),
        );
        if hwnd.is_null() {
            COUNT.store(0, Ordering::SeqCst);
            return;
        }
        HWND_SLOT.store(hwnd as _, Ordering::SeqCst);
        SetLayeredWindowAttributes(hwnd, 0, 230, LWA_ALPHA);
        SetWindowPos(
            hwnd,
            HWND_TOPMOST,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
        );
        ShowWindow(hwnd, SW_SHOWNOACTIVATE);
        UpdateWindow(hwnd);
        let mut msg = std::mem::zeroed();
        while GetMessageW(&mut msg, ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        HWND_SLOT.store(ptr::null_mut(), Ordering::SeqCst);
        DestroyWindow(hwnd);
    }
}

unsafe extern "system" fn wnd_proc(
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if msg == WM_PAINT {
        let mut paint = std::mem::zeroed();
        let hdc = BeginPaint(hwnd, &mut paint);
        let brush = CreateSolidBrush(RGB(140, 32, 32));
        FillRect(hdc, &paint.rcPaint, brush);
        DeleteObject(brush as _);
        SetBkMode(hdc, TRANSPARENT as i32);
        SetTextColor(hdc, RGB(255, 255, 255));
        let text = LABEL
            .lock()
            .map(|slot| wide(&slot))
            .unwrap_or_else(|_| wide("Helper has control"));
        let mut rect = paint.rcPaint;
        DrawTextW(
            hdc,
            text.as_ptr(),
            -1,
            &mut rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE,
        );
        EndPaint(hwnd, &paint);
        return 0;
    }
    if msg == WM_CLOSE || msg == WM_DESTROY {
        PostQuitMessage(0);
        return 0;
    }
    DefWindowProcW(hwnd, msg, wparam, lparam)
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}
