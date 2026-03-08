#![no_main]
#![no_std]

use core::mem::MaybeUninit;
use uefi::boot::{self, LoadImageSource};
use uefi::prelude::*;
use uefi::proto::device_path::{DevicePath, build};
use uefi::proto::loaded_image::LoadedImage;
use uefi::proto::BootPolicy;
use uefi::{CStr16, Status, cstr16, println};

// Try vmlinuz-lts first (for physical hardware), fallback to vmlinuz-virt (for VMs)
const KERNEL_PATH_LTS: &CStr16 = cstr16!("\\vmlinuz-lts");
const KERNEL_PATH_VIRT: &CStr16 = cstr16!("\\vmlinuz-virt");
const KERNEL_CMDLINE: &CStr16 =
    cstr16!("console=ttyS0,115200 rdinit=/init loglevel=7 initrd=\\alpine-initramfs.img");

#[entry]
fn main() -> Status {
    if let Err(status) = run() {
        println!("launcher failed: {:?}", status);
        return status;
    }

    Status::SUCCESS
}

fn run() -> core::result::Result<(), Status> {
    println!("Rust EFI launcher: preparing Linux EFI stub...");

    let parent = boot::image_handle();
    let loaded = boot::open_protocol_exclusive::<LoadedImage>(parent)
        .map_err(|err| err.status())?;
    let device = loaded.device().ok_or(Status::NOT_FOUND)?;
    drop(loaded);

    let device_path = boot::open_protocol_exclusive::<DevicePath>(device)
        .map_err(|err| err.status())?;

    // Try LTS kernel first, fallback to virt kernel
    let kernel_path = KERNEL_PATH_LTS;
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

    let kernel_handle = boot::load_image(
        parent,
        LoadImageSource::FromDevicePath {
            device_path: kernel_device_path.clone(),
            boot_policy: BootPolicy::ExactMatch,
        },
    );

    let kernel_handle = match kernel_handle {
        Ok(handle) => {
            println!("Loaded kernel: vmlinuz-lts");
            handle
        }
        Err(_) => {
            // Fallback to virt kernel
            println!("vmlinuz-lts not found, trying vmlinuz-virt...");
            let mut kernel_path_buf = [MaybeUninit::uninit(); 1024];
            let mut builder = build::DevicePathBuilder::with_buf(&mut kernel_path_buf);
            for node in device_path.node_iter() {
                builder = builder.push(&node).map_err(|_| Status::BUFFER_TOO_SMALL)?;
            }
            let kernel_device_path = builder
                .push(&build::media::FilePath {
                    path_name: KERNEL_PATH_VIRT,
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
            .map_err(|err| err.status())?
        }
    };
    drop(device_path);

    let mut kernel_image = boot::open_protocol_exclusive::<LoadedImage>(kernel_handle)
        .map_err(|err| err.status())?;
    unsafe {
        kernel_image.set_load_options(
            KERNEL_CMDLINE.as_ptr().cast(),
            u32::try_from(KERNEL_CMDLINE.num_bytes()).unwrap(),
        );
    }
    drop(kernel_image);

    println!("Rust EFI launcher: starting kernel...");
    boot::start_image(kernel_handle).map_err(|err| err.status())?;
    Ok(())
}
