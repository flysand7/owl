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

/*
Value for some parameters specifying that the library should pick a value. The places where this
value is allowed are explicitly documented.
*/
DONT_CARE := min(int)

/*
Hints for window initialization.
*/
Window_Hints :: struct {
	title: string,
	position_x: int,
	position_y: int,
	size_x: int,
	size_y: int,
}

/*
Return a default set of hints.

## Description

This procedure returns the set of default window hints. The values are as follows:
- `title`: `"OWL Window"`
- `position_x`: `DONT_CARE`
- `position_y`: `DONT_CARE`
- `size_x`: `DONT_CARE`
- `size_y`: `DONT_CARE`
*/
hints_default :: proc() -> Window_Hints {
	return {
		title = "OWL Window",
		position_x = DONT_CARE,
		position_y = DONT_CARE,
		size_x = DONT_CARE,
		size_y = DONT_CARE,
	}
}

/*
Specify that you want a specific title on your window.

## Lifetimes

The provided string must be alive during the time between specifying this hint is specified and the
call to `create_window()`. The library borrows the string for that period. During the call to
`create_window()`, this string may be transformed to a cstring using the temporary allocator.
*/
hint_title :: proc(hints: ^Window_Hints, title: string) {
	hints.title = title
}

/*
Specify that you want a window at a specific position.

## Description

This procedure sets the desired position of the window, in screen coordinates, or, if `DONT_CARE`
is specified for either coordinate, the window is displayed such that it is centered. The default
value of this hint is `DONT_CARE`.

In case a coordinate is specified, the position values must be non-negative.
*/
hint_position :: proc(hints: ^Window_Hints, position_x: int, position_y: int) {
	hints.position_x = position_x
	hints.position_y = position_y
}

/*
Specify that a window needs to have a specific size.

## Description

This procedure sets the desired size of the window, in screen coordinates, or, if `DONT_CARE` is
specified for either coordinate, the window's size is chosen to be 1280x720.

## Remark (tiled window managers)

In case a tiled window manager is used (typically on linux), the window size can not be controlled
by the user and instead is decided by the window manager. Do not assume that the size of the window
is the same as you asked it to be with this hint, always verify the size after the window has been
created.
*/
hint_size :: proc(hints: ^Window_Hints, size_x: int, size_y: int) {
	hints.size_x = size_x
	hints.size_y = size_y
}

/*
Semi-opaque structure representing a window.
*/
Window :: struct {
	using _: OS_Window,
	size_x: int,
	size_y: int,
	position_x: int,
	position_y: int,
}

/*
Create the window.

## Params
- `hints`: The set of hints to provide for window initialization, or `nil` to use the default.

## Description

This function creates the window and returns a semi-opaque pointer to the `window` structure.
Look at documentation for the hint-initialization function to know which options are available.

Here's a short example of how you can use this function to create a window.

```
hints := owl.hints_default()
owl.hint_position(&hints, 0, 0)
owl.hint_size(&hints, 1280, 720)
owl.hint_title(&hints, "My cool-ass title")
window := create_window(&hints)
assert(window != nil, "Window creation failed")
```

## Thread-safety

This procedure is not thread-safe as long as allocation procedures of the specified permanent
allocator are not synchronized.
*/
window_create :: proc(hints: ^Window_Hints) -> ^Window {
	if hints == nil {
		default_hints := hints_default()
		return os_window_create(&default_hints)
	} else {
		return os_window_create(hints)
	}
}


/*
Destroy a window.

## Description

This procedure closes the window and deallocates the associated memory. You can call this function
when the window is open or closed, and the window is guaranteed to be destroyed.

You can not call any procedures using the destroyed window as a parameter.
*/
window_destroy :: proc(window: ^Window) {
	os_window_destroy(window)
}
