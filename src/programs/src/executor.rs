use core::ptr;

use common::context::*;
use common::elf::*;
use common::memory;
use common::resource::URL;
use common::scheduler;
use common::string::String;
use common::vec::Vec;

pub fn execute(url: &URL, wd: &URL, args: &Vec<String>) {
    unsafe {
        let mut physical_address = 0;
        let virtual_address = 0x80000000;
        let mut virtual_size = 0;
        let mut entry = 0;

        if let Some(mut resource) = url.open() {
            let mut vec: Vec<u8> = Vec::new();
            resource.read_to_end(&mut vec);

            let executable = ELF::from_data(vec.as_ptr() as usize);

            if executable.data > 0 {
                virtual_size = memory::alloc_size(executable.data) - 4096;
                physical_address = memory::alloc(virtual_size);
                ptr::copy((executable.data + 4096) as *const u8,
                          physical_address as *mut u8,
                          virtual_size);
                entry = executable.entry();
            }
        }

        if physical_address > 0 && virtual_address > 0 && virtual_size > 0 &&
           entry >= virtual_address && entry < virtual_address + virtual_size {
            let mut context_args: Vec<usize> = Vec::new();
            context_args.push(0); // ENVP
            context_args.push(0); // ARGV NULL
            let mut argc = 1;
            for i in 0..args.len() {
                if let Option::Some(arg) = args.get(args.len() - i - 1) {
                    context_args.push(arg.to_c_str() as usize);
                    argc += 1;
                }
            }
            context_args.push(url.string.to_c_str() as usize);
            context_args.push(argc);

            let mut context = Context::new(entry, &context_args);

            //TODO: Push arg c_strs as things to clean up
            context.memory.push(ContextMemory {
                physical_address: physical_address,
                virtual_address: virtual_address,
                virtual_size: virtual_size,
            });

            context.cwd = wd.to_string();

            if let Some(stdin) = URL::from_str("debug://").open() {
                context.files.push(ContextFile {
                    fd: 0, // STDIN
                    resource: stdin,
                });
            }

            if let Some(stdout) = URL::from_str("debug://").open() {
                context.files.push(ContextFile {
                    fd: 1, // STDOUT
                    resource: stdout,
                });
            }

            if let Some(stderr) = URL::from_str("debug://").open() {
                context.files.push(ContextFile {
                    fd: 2, // STDERR
                    resource: stderr,
                });
            }

            let reenable = scheduler::start_no_ints();
            if contexts_ptr as usize > 0 {
                (*contexts_ptr).push(context);
            }
            scheduler::end_no_ints(reenable);
        } else if physical_address > 0 {
            memory::unalloc(physical_address);
        }
    }
}
