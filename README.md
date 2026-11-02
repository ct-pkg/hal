# hal — the Wave 1 hardware abstraction contract

> English · [中文](#中文)

`hal` is a **contract-only** CT package: four traits, no implementation and
no C output. A platform package such as
[`hal-posix`](https://github.com/ct-pkg/hal-posix) publishes global instances
and binds these traits to real calls; a consumer imports the traits and boxes
the platform instance.

| Trait | Methods | Meaning |
| --- | --- | --- |
| `hal::Uart` | `send(buf, len)` / `recv(buf, len)` | byte-oriented serial port; returns the count or a negative error |
| `hal::Gpio` | `read(pin)` / `write(pin, value)` | pin level; `read` returns 0 / 1 or a negative error, `write` returns 0 on success |
| `hal::Clock` | `now_ms()` | monotonically non-decreasing milliseconds; only differences matter |
| `hal::Log` | `write(buf, len)` | diagnostic stream; returns the count or a negative error |

## Usage

```sh
ct get hal@^1.0.0
```

```ct
import Uart;
import Gpio;
import Clock;
import Log;
import PosixHal;              /* the platform package's instance */

hal::Uart u = posix_hal;
u.send("ok\n", 3);
```

The contract is frozen at `1.0.0`; a breaking change moves it to `2.0.0`.

## 中文

`hal` 是**纯契约**包：四个 trait，没有实现、不产 C 产物。平台包（如
`hal-posix`）发布全局实例并把这四个 trait 绑到真实调用上；消费方导入 trait 后把平台实例装箱。

用法与上表相同：`ct get hal@^1.0.0`，再 `import Uart;` 等，最后 `hal::Uart u = posix_hal;`。
契约在 `1.0.0` 冻结，破坏性变更走 `2.0.0`。

## Licence

MIT — see [LICENSE](LICENSE).
