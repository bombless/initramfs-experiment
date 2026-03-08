#![no_main]
#![no_std]

use core::mem::MaybeUninit;
use uefi::boot::{self, LoadImageSource};
use uefi::prelude::*;
use uefi::proto::console::text::Key;
use uefi::proto::device_path::{DevicePath, build};
use uefi::proto::loaded_image::LoadedImage;
use uefi::proto::BootPolicy;
use uefi::{
    CStr16, Status, cstr16, println,
    runtime::{self, ResetType},
    system,
};

// Prefer vmlinuz-lts (physical hardware), fallback to vmlinuz-virt (VMs).
const KERNEL_PATH_LTS: &CStr16 = cstr16!("\\vmlinuz-lts");
const KERNEL_PATH_VIRT: &CStr16 = cstr16!("\\vmlinuz-virt");
const KERNEL_NAME_LTS: &str = "vmlinuz-lts";
const KERNEL_NAME_VIRT: &str = "vmlinuz-virt";
const KERNEL_CMDLINE: &CStr16 =
    cstr16!("console=ttyS0,115200 rdinit=/init loglevel=7 initrd=\\alpine-initramfs.img");

#[derive(Copy, Clone)]
struct KernelCandidate {
    name: &'static str,
    path: &'static CStr16,
}

const KERNEL_CANDIDATES: [KernelCandidate; 2] = [
    KernelCandidate {
        name: KERNEL_NAME_LTS,
        path: KERNEL_PATH_LTS,
    },
    KernelCandidate {
        name: KERNEL_NAME_VIRT,
        path: KERNEL_PATH_VIRT,
    },
];

#[derive(Copy, Clone)]
enum MenuAction {
    BootKernel,
    Shutdown,
    Reboot,
}

#[entry]
fn main() -> Status {
    if let Err(status) = run() {
        println!("launcher failed: {:?}", status);
        return status;
    }

    Status::SUCCESS
}

fn run() -> core::result::Result<(), Status> {
    let mut kernel_hint = probe_available_kernel_name()?;

    loop {
        print_menu(kernel_hint);

        match read_menu_action()? {
            MenuAction::BootKernel => match boot_first_available_kernel() {
                Ok(kernel_name) => {
                    println!("Kernel image returned to launcher: {}", kernel_name);
                }
                Err(status) => {
                    println!("Boot failed: {:?}", status);
                }
            },
            MenuAction::Shutdown => runtime::reset(ResetType::SHUTDOWN, Status::SUCCESS, None),
            MenuAction::Reboot => runtime::reset(ResetType::COLD, Status::SUCCESS, None),
        }

        kernel_hint = probe_available_kernel_name()?;
    }
}

fn print_menu(kernel_hint: Option<&'static str>) {
    println!();
    println!("=== Rust EFI Launcher ===");
    match kernel_hint {
        Some(name) => println!("1) Boot Linux kernel ({})", name),
        None => println!("1) Boot Linux kernel (no kernel file found)"),
    }
    println!("2) Shutdown");
    println!("3) Reboot");
    println!("Press 1/2/3.");
}

fn read_menu_action() -> core::result::Result<MenuAction, Status> {
    system::with_stdin(
        |stdin| -> core::result::Result<MenuAction, Status> {
            loop {
                let wait_event = stdin.wait_for_key_event().ok_or(Status::UNSUPPORTED)?;
                let mut events = [wait_event];
                boot::wait_for_event(&mut events).map_err(|err| err.status())?;

                match stdin.read_key().map_err(|err| err.status())? {
                    Some(Key::Printable(ch)) if ch == '1' || ch == 'b' || ch == 'B' => {
                        return Ok(MenuAction::BootKernel);
                    }
                    Some(Key::Printable(ch)) if ch == '2' || ch == 's' || ch == 'S' => {
                        return Ok(MenuAction::Shutdown);
                    }
                    Some(Key::Printable(ch)) if ch == '3' || ch == 'r' || ch == 'R' => {
                        return Ok(MenuAction::Reboot);
                    }
                    _ => {
                        println!("Invalid input. Press 1, 2, or 3.");
                    }
                }
            }
        },
    )
}

fn probe_available_kernel_name() -> core::result::Result<Option<&'static str>, Status> {
    with_boot_device_path(|parent, device_path| {
        for candidate in &KERNEL_CANDIDATES {
            match load_kernel_image(parent, device_path, candidate.path) {
                Ok(handle) => {
                    boot::unload_image(handle).map_err(|err| err.status())?;
                    return Ok(Some(candidate.name));
                }
                Err(_) => continue,
            }
        }

        Ok(None)
    })
}

fn boot_first_available_kernel() -> core::result::Result<&'static str, Status> {
    with_boot_device_path(|parent, device_path| {
        for candidate in &KERNEL_CANDIDATES {
            let kernel_handle = match load_kernel_image(parent, device_path, candidate.path) {
                Ok(handle) => handle,
                Err(_) => continue,
            };

            println!("Loaded kernel: {}", candidate.name);
            set_kernel_cmdline(kernel_handle)?;
            println!("Rust EFI launcher: starting kernel...");
            boot::start_image(kernel_handle).map_err(|err| err.status())?;
            return Ok(candidate.name);
        }

        Err(Status::NOT_FOUND)
    })
}

fn set_kernel_cmdline(kernel_handle: Handle) -> core::result::Result<(), Status> {
    let mut kernel_image = boot::open_protocol_exclusive::<LoadedImage>(kernel_handle)
        .map_err(|err| err.status())?;
    let load_options_len =
        u32::try_from(KERNEL_CMDLINE.num_bytes()).map_err(|_| Status::BAD_BUFFER_SIZE)?;

    unsafe {
        kernel_image.set_load_options(KERNEL_CMDLINE.as_ptr().cast(), load_options_len);
    }

    Ok(())
}

fn with_boot_device_path<F, R>(mut f: F) -> core::result::Result<R, Status>
where
    F: FnMut(Handle, &DevicePath) -> core::result::Result<R, Status>,
{
    let parent = boot::image_handle();
    let loaded = boot::open_protocol_exclusive::<LoadedImage>(parent)
        .map_err(|err| err.status())?;
    let device = loaded.device().ok_or(Status::NOT_FOUND)?;
    drop(loaded);

    let device_path = boot::open_protocol_exclusive::<DevicePath>(device)
        .map_err(|err| err.status())?;
    f(parent, &device_path)
}

fn load_kernel_image(
    parent: Handle,
    device_path: &DevicePath,
    kernel_path: &CStr16,
) -> core::result::Result<Handle, Status> {
    let mut kernel_path_buf = [MaybeUninit::uninit(); 1024];
    let mut builder = build::DevicePathBuilder::with_buf(&mut kernel_path_buf);
    for node in device_path.node_iter() {
        builder = builder.push(&node).map_err(|_| Status::BUFFER_TOO_SMALL)?;
    }
    let kernel_device_path = builder
        .push(&build::media::FilePath {
            path_name: kernel_path,
        })
        .map_err(|_| Status::BUFFER_TOO_SMALL)?
        .finalize()
        .map_err(|_| Status::BUFFER_TOO_SMALL)?;

    boot::load_image(
        parent,
        LoadImageSource::FromDevicePath {
            device_path: kernel_device_path,
            boot_policy: BootPolicy::ExactMatch,
        },
    )
    .map_err(|err| err.status())
}
