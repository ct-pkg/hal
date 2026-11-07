/*
 * Clock.shim.h - the one C symbol behind hal::Clock.nowMs().
 *
 * Declaration only: `hal` has no implementation. Either a platform package
 * (hal-posix) or the application defines `hal_platform_now_ms`; it must return
 * a monotonically non-decreasing millisecond count whose origin is arbitrary.
 * Do not add a body here.
 */
int hal_platform_now_ms(void);
