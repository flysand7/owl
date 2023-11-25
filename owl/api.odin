package owl

/*
Errors returned by this library.
*/
Error :: enum {
	// No error.
	None,
	// Window manager not found. This can happen during library initialization, if
	// `$WAYLAND_DISPLAY` nor `$DISPLAY` environment variable isn't set.
	No_Window_Manager,
}

/*
Initialization hints.
*/
Init_Hints :: bit_set[Init_Hint_Bit]
Init_Hint_Bit :: enum {
	// Enable internal logging.
	Logger,
	// Prefer X11 context, if available. This option is ignored on non-linux platforms.
	Linux_X11,
	// Prefer wayland context, if available. This option is ignored on non-linux platforms.
	Linux_Wayland,
}

/*
Library initialization.

## Description

You **must** initialize the library in order to use it. The functions that require the library
to be initialized do not perform checks of whether it is initialized, most likely the behavior
upon using the library without initialization is a crash.

The logger is set from the context. If `.Logger` is not specified in hints, the logger argument
is ignored.

For internal allocations the library uses allocations that can be overridden once during library
initialization. The allocators can be overridden by the user. The library allocates memory **only**
using the allocators set by the init function.

The permanent allocator must implement `.Free` and `.Resize` modes. The library manages the
permanent allocator. User should not manually free anything that is allocated using the permanent
allocator. No requirements are imposed for temporary allocator. The user can use `.Free_All`
function to free all allocations made by this library on per-frame basis. The library explicitly
documents whether values returned to the user are temporary or permanent and whether they are
allowed to be freed. Though in most situations temporary allocations don't reach the user.

The library may do allocations outside of the scope of the provided allocators, for example when it
calls into libc or Xlib (linux) functions that allocate memory under the hood. Freeing the
allocators manually does not free all the memory. Call `terminate()` to ensure everything that has
been allocated by the library is freed.

## Remark (linux)

This function will detect the presence of wayland and x11 on the system based on the current
type of the session, according to `$WAYLAND_DISPLAY` and `$DISPLAY` environment variables. The
check is done as follows:

1. First, `$WAYLAND_DISPLAY` environment variable is checked. If set, the value is used as
the wayland display. If unset or wayland initialization failed, we proceed to the second step.

2. The `$DISPLAY` environment variable is checked. If set, the value is used as the x11
display. If unset or x11 initialization failed, the `.No_Window_Manager` error is returned.

If `Init_Hints` specifies x11 or wayland, the order of steps is changed such that the
respective window manager is checked first.

## Synchronization

This function is not synchronized. Do not call it from multiple threads.

## Errors

- `No_Window_Manager` is returned, if no window manager was found, or none of avialable window
	managers could be initialized successfully.
*/
init :: proc(
	hints:     Init_Hints,
	logger     := context.logger,
	perm_alloc := context.allocator,
	temp_alloc := context.temp_allocator,
	loc        := #caller_location
) -> Error {
	context.logger = logger
	return os_init(hints, logger, perm_alloc, temp_alloc, loc)
}

/*
Library termination.

## Description

This function terminates the library. Frees all the resources initialized by the library, destroys
all resources that were allocated by the library etc.

This function does not free objects allocated in the temporary allocator. It is the user's
responsibility to manage the temporary allocator whenever objects allocated by the library in
temporary storage are no longer needed.

It is possible to initialize and terminate the library multiple times.

**DO NOT** call this function if `init` returned an error.

## Synchronization

This function is not thread safe.
*/
terminate :: proc() {
	os_terminate()
}
