function void *
OS_Reserve(U64 size)
{
	mach_port_t task = mach_task_self();
	void *ptr = 0;

	kern_return_t kr = vm_allocate(task, (vm_address_t *)&ptr, size, VM_FLAGS_ANYWHERE);
	if (kr != KERN_SUCCESS)
	{
		return 0;
	}

	kr = vm_protect(task, (vm_address_t)ptr, size, 0, VM_PROT_NONE);
	if (kr != KERN_SUCCESS)
	{
		return 0;
	}

	return ptr;
}

function B32
OS_Commit(void *ptr, U64 size)
{
	mach_port_t task = mach_task_self();
	vm_prot_t prot = VM_PROT_READ | VM_PROT_WRITE;
	kern_return_t kr = vm_protect(task, (vm_address_t)ptr, size, 0, prot);
	return kr == KERN_SUCCESS;
}

function void
_OS_Decommit(void *ptr, U64 size)
{
	mach_port_t task = mach_task_self();
	kern_return_t kr = vm_protect(task, (vm_address_t)ptr, size, 0, VM_PROT_NONE);
	if (kr != KERN_SUCCESS)
	{
		return;
	}

	vm_behavior_set(task, (vm_address_t)ptr, size, VM_BEHAVIOR_REUSABLE);
}

function void
_OS_Release(void *ptr, U64 size)
{
	mach_port_t task = mach_task_self();
	vm_deallocate(task, (vm_address_t)ptr, size);
}
