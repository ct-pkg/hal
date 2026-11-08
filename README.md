# hal — 硬件抽象契约

## 1. 定位与边界

`hal` 是 CT 的硬件抽象**契约包**：三个 `pub trait`（`Uart`/`Gpio`/`Log`）加一个 namespace 入口（`hal::Clock`），没有任何实现。它让业务代码依赖“一个串口”“一个时钟”，而不依赖某块板子、某个 OS 或某个驱动；具体实现由平台包（如 [`hal-posix`](https://github.com/ct-pkg/hal-posix)）提供，应用在 `main` 里选择并装箱。

| 入口 | 方法 | 形态 | 含义 |
| --- | --- | --- | --- |
| `hal::Uart` | `send(buf, len)` / `recv(buf, len)` | `pub trait` | 面向字节的同步串口 |
| `hal::Gpio` | `read(pin)` / `write(pin, value)` | `pub trait` | 引脚电平 |
| `hal::Clock` | `nowMs()` | namespace 入口 | 单调不减的毫秒计数 |
| `hal::Log` | `write(buf, len)` | `pub trait` | 诊断输出流 |

**明确不做的事：**

- 不是驱动，也不是平台适配层：包里没有 struct、没有全局变量、没有 `impl`、没有函数体，不产生自己的 C 翻译单元。
- 不提供任何实例（没有 `posix_hal` 之类），因此单独安装 `hal` 无法写出可执行程序。
- 不定义缓冲大小、波特率、阻塞语义、引脚编号、日志目的地；这些由实现方规定。
- 不拥有对象、不引用计数、不做空值检查；接口值只借用。
- `Clock` 不是接口类型：不能声明变量、不能装箱、不能作为参数传递，只能直接调用 `hal::Clock.nowMs()`。

## 2. 依赖与安装

- **包依赖**：`ct.pkg` 中没有 `dep`、没有 `cflags`、没有 `ldflags`、没有 `requires`；不强制编译器版本。
- **编译器**：`namespace`、`import`、`pub`、`ct build` 需要 ct-ast 系列编译器。本文所有命令与输出在 `ct v0.19.1` 上实测；冻结的 L0 `ctc` 不接受这些语法。
- **链接要求**：`hal` 只声明、不定义。调用 `hal::Clock.nowMs()` 的程序必须在链接期提供 `int hal_platform_now_ms(void)`；三个 trait 不需要任何额外符号。
- **平台限制**：`hal` 自身跨平台；可用性取决于实现方。`hal-posix` 面向 POSIX（macOS/Linux）。
- **安装**：包名 `hal`，当前版本 `0.1.0`，尚未打 tag。`ct-pkg/index/packages.txt` 中的条目目前是注释状态，要等 `v0.1.0` 推送后再启用；在此之前在仓库内直接用 `-I` 指向本目录。索引启用后可按 `ct get hal@^0.1.0` 安装，再由 `ct install` 生成构建命令。
- **引入方式**：按单元名 `import`，目标只能是 `<name>.h.ct` 或映射单元 `<name>.m.ct`；普通 `.ct` 不发布接口，不能被 import。四个单元分别是 `hal::Uart`、`hal::Gpio`、`hal::Log`、`hal::Clock`（后者是 `.m.ct`）。
- **限定名规则**：引入 trait 后直接写 `Uart`，不要写 `hal::Uart`（参数位置写限定名会报 `error: expected a parameter name`，见第 7 节）；`Clock` 相反，必须写 `hal::Clock.nowMs()`。

## 3. 快速开始

`hal` 没有实现，所以最小可用程序要自己实现其中一个 trait。下面两个文件是完整示例，同一对单元也放在 [`examples/fake-uart/`](examples/fake-uart/) 下，只依赖 `Uart` 契约，不依赖 `hal-posix`。

`FakeUart.h.ct`：

```ct
import hal::Uart;
#include <stdio.h>

pub struct FakeUart {
    int sent;
} use Uart;

impl Uart for FakeUart {
    int send(char *buf, int len) {
        if (len < 0) return -1;
        (void)buf;
        printf("[fake-uart] send %d byte(s)\n", len);
        self->sent = self->sent + len;
        return len;
    }

    int recv(char *buf, int len) {
        (void)buf;
        (void)len;
        return 0;
    }
}
```

`main.ct`：

```ct
#include <stdio.h>

import hal::Uart;
import FakeUart;

void emit(Uart u, char *msg, int len) {
    u.send(msg, len);
}

int main(void) {
    FakeUart f = { .sent = 0 };

    emit(f, "hello\n", 6);
    emit(f, "hal\n", 4);

    Uart u = f;
    u.send("direct\n", 7);

    printf("FakeUart.sent = %d\n", f.sent);
    return 0;
}
```

构建并运行（只把入口单元传给 `ct build`；`FakeUart.h.ct` 由 `import FakeUart;` 从同目录解析）：

```sh
ct build -I . examples/fake-uart/main.ct -o /tmp/fake-uart
/tmp/fake-uart
```

预期输出：

```text
[fake-uart] send 6 byte(s)
[fake-uart] send 4 byte(s)
[fake-uart] send 7 byte(s)
FakeUart.sent = 17
```

`ct build` 最后调用的是下面这行 C 编译器命令（`.ctbuild/*.c` 由 `ct build` 生成；实测可手动重跑，输出相同）：

```sh
cc -std=c99 .ctbuild/main.c .ctbuild/Uart.c .ctbuild/FakeUart.c -o demo
```

要点：

- `import hal::Uart;` 引入 `hal/hal/Uart.h.ct` 的 `hal::Uart`；路径里有两个 `hal`，前一个是仓库目录，后一个是 namespace 目录。
- `pub struct FakeUart ... use Uart;` 声明这个 struct 满足该 trait。trait 与 struct **都**为 `pub`，跨单元派发才成立。
- `impl Uart for FakeUart` 提供全部方法；方法体内用 `self` 指代对象，trait 声明里没有接收者参数。
- 带 `impl` 的单元必须是 `.h.ct`，否则不能被 import。

## 4. API 全表

三个 trait 的方法和 `nowMs()` 都是**同步**的。`char *buf` 只在调用期间借用：实现不得保留指针、不得释放、不得缓存。任何方法都不转移所有权，也不返回指针。

### 4.1 `hal::Uart`（`Uart.h.ct`）

| 方法 | 签名 | 成功返回 | 失败返回 | 副作用 |
| --- | --- | --- | --- | --- |
| `send` | `int send(char *buf, int len)` | 实际传输字节数，`0..len` | 负数 | 借用 `buf`；写入实现方的发送侧。允许短写，不承诺写满 |
| `recv` | `int recv(char *buf, int len)` | 实际收到字节数，`0..len` | 负数 | 借用 `buf`；填充收到的字节。`0` 可能表示“当前没有数据” |

`len >= 0`；`len == 0` 合法。`len > 0` 时 `buf` 至少可读/可写 `len` 字节。缓冲、波特率、阻塞与帧格式契约一字未提，由实现方规定。

### 4.2 `hal::Gpio`（`Gpio.h.ct`）

| 方法 | 签名 | 成功返回 | 失败返回 | 副作用 |
| --- | --- | --- | --- | --- |
| `read` | `int read(int pin)` | `0` 或 `1` | 负数（`pin` 越界） | 读取电平；不分配内存 |
| `write` | `int write(int pin, int value)` | `0` | 负数（`pin` 越界） | 驱动电平；`value` 非零为高。不保证可回读 |

引脚编号、电气特性、是否真硬件完全由实现方决定。

### 4.3 `hal::Clock`（`Clock.m.ct`，namespace 入口）

| 方法 | 签名 | 成功返回 | 失败返回 | 副作用 |
| --- | --- | --- | --- | --- |
| `nowMs` | `int nowMs()`（调用写 `hal::Clock.nowMs()`） | 单调不减的毫秒计数 | 无（契约不定义失败） | 无参数、无所有权；绑定全局 C 符号 `hal_platform_now_ms` |

原点**未定义**，只有两次读数之差有意义；不要和墙钟纪元比较，也不要假设分辨率。`hal-posix` 把原点定在第一次调用，返回 `CLOCK_MONOTONIC` 毫秒。

### 4.4 `hal::Log`（`Log.h.ct`）

| 方法 | 签名 | 成功返回 | 失败返回 | 副作用 |
| --- | --- | --- | --- | --- |
| `write` | `int write(char *buf, int len)` | 实际写出字节数，`0..len` | 负数 | 借用 `buf`；写入诊断流。不保证 flush |

输出目的地由实现方定义（`hal-posix` 用 fd 2）。

## 5. 教程正文

### 5.1 纯契约长什么样

`hal` 的全部内容就是四个单元：三个 trait 单元加一个 `Clock.m.ct` namespace 入口。没有状态、没有构造、没有析构，也没有默认实现；唯一的外部依赖是时钟符号 `hal_platform_now_ms`。构建消费者时，`Uart.c` 等单元只有空壳，不含任何实现符号；`Clock.m.ct` 连 `.c` 都不生成，只把 `int hal_platform_now_ms(void);` 的声明注入消费者 TU。

### 5.2 实现一个契约需要三件事

以 `Uart` 为例（完整可运行代码见第 3 节）：

1. 写一个 `pub struct`，用 `... use Uart;` 声明它满足该 trait；
2. 用 `impl Uart for MyUart { ... }` 实现 trait 的**全部**方法；
3. 把文件命名为 `.h.ct`，这样其他单元才能 import。

一个 struct 可以同时 `use Uart, Gpio, Log`，再用多个 `impl` 分别实现（第 6.1 节有完整示例）。`Clock` 不参与这套机制：它没有对象，也没有 `impl`。

### 5.3 装箱与派发

trait 值是一个胖指针 `{ self, vt }`：`self` 指向对象，`vt` 指向该 struct 对该 trait 的虚表。把实现了 `Uart` 的对象赋给 `Uart` 变量，或传给 `Uart` 参数，编译器自动装箱；虚表名形如 `FakeUart_hal_Uart_vtable`。

- **借用，不拥有。** 接口值不引用计数、不释放对象；对象必须先于接口值销毁。
- 对象已死、接口值还在，就是悬垂指针；接口值为 `{0,0}` 时派发会崩溃，`hal` 不做空值检查。
- 没有向下转型，也没有运行时类型查询。

### 5.4 跨单元可见性与单元后缀

虚表只有在 trait 和 struct **都**为 `pub` 时才以外部链接发出；否则它是 `static`，其他单元装箱会在 C 编译阶段失败（报错原文见第 7 节）。`hal` 的三个 trait 已经是 `pub`，你只需要把自己的实现 struct 标成 `pub`。

`import` 只认 `<name>.h.ct` 和映射单元 `<name>.m.ct`；普通 `.ct` 不发布接口，无法被 import。入口单元本身可以是普通 `.ct`。

### 5.5 为什么 `Clock` 是 namespace 入口

“读当前时间”是零参能力，没有有意义的接收者；强行做成 trait 就得先造一个空对象再调用，毫无价值。因此 `Clock.m.ct` 把它声明成静态映射：

```ct
pub trait Clock {
    int nowMs();
}

map trait Clock for namespace hal {
    nowMs() -> hal_platform_now_ms();
}
```

调用必须写限定名 `hal::Clock.nowMs()`；只 import 后裸写 `Clock.nowMs()` 会报 `use of an undeclared variable`（见第 7 节）。`Clock` 不能装箱、不能作为参数传递，也不能 `Clock c = ...`。

时钟替换只能发生在链接期：换掉 `hal_platform_now_ms` 的定义即可（第 6.4 节）。符号名是契约的一部分，写错不会在 CT 层报错，而是在 C 链接期得到 `undefined reference`。

### 5.6 与平台包如何对接

以 `hal-posix` 为例：

- 平台包提供 `pub struct PosixHal posix_hal;`，用 `map trait Uart for instance posix_hal`、`map trait Gpio for instance posix_hal`、`map trait Log for instance posix_hal` 把三个 trait 绑到自己的 C 函数；
- 平台包定义 `int hal_platform_now_ms(void)`，供 `hal::Clock.nowMs()` 使用；
- 应用 `import PosixHal;` 后，把同一个 `posix_hal` 装箱成需要的 trait，时钟直接调用 `hal::Clock.nowMs()`。

`Clock` 不参与装箱。具体行为、构建参数与限制见 [`hal-posix` README](https://github.com/ct-pkg/hal-posix/blob/main/README.md)。

## 6. 常见配方

以下每个程序都在 `ct v0.19.1` 上实际编译运行过；命令统一为 `ct build -I <hal 目录> main.ct -o demo`。

### 6.1 实现一个完整的自有后端（三个 trait 一个 struct）

`AllFake.h.ct`：

```ct
import hal::Uart;
import hal::Gpio;
import hal::Log;
#include <stdio.h>

pub struct AllFake {
    int sent;
    int pins;
} use Uart, Gpio, Log;

impl Uart for AllFake {
    int send(char *buf, int len) {
        if (len < 0) return -1;
        (void)buf;
        self->sent = self->sent + len;
        return len;
    }
    int recv(char *buf, int len) {
        (void)buf;
        (void)len;
        return 0;
    }
}

impl Gpio for AllFake {
    int read(int pin) {
        if (pin < 0 || pin >= 8) return -1;
        return (self->pins >> pin) & 1;
    }
    int write(int pin, int value) {
        if (pin < 0 || pin >= 8) return -1;
        if (value) self->pins = self->pins | (1 << pin);
        else self->pins = self->pins & ~(1 << pin);
        return 0;
    }
}

impl Log for AllFake {
    int write(char *buf, int len) {
        (void)buf;
        return len;
    }
}
```

时钟不在这个 struct 里。`main.ct` 自带一个步进 10ms 的链接期替身：

```ct
#include <stdio.h>
import hal::Uart;
import hal::Gpio;
import hal::Clock;
import hal::Log;
import AllFake;

int fake_t = 0;

int hal_platform_now_ms(void) {
    fake_t = fake_t + 10;
    return fake_t;
}

int main(void) {
    AllFake a = { .sent = 0, .pins = 0 };
    Uart u = a;
    Gpio g = a;
    Log l = a;

    u.send("hi\n", 3);
    g.write(3, 1);
    printf("pin3=%d\n", g.read(3));
    int t0 = hal::Clock.nowMs();
    int t1 = hal::Clock.nowMs();
    printf("t0=%d t1=%d\n", t0, t1);
    l.write("log\n", 4);
    printf("sent=%d pins=%d\n", a.sent, a.pins);
    return 0;
}
```

预期输出：

```text
pin3=1
t0=10 t1=20
sent=3 pins=8
```

所有接口值都借用同一个 `a`；`a` 必须在它们之前声明、之后销毁。时钟替身是进程级的，不借用 `a`。

### 6.2 记录内容的 Uart 替身

`FakeUart` 只统计字节数。要检查内容，用 `MemUart` 把字节存进自己的缓冲区。`MemUart.h.ct`：

```ct
import hal::Uart;

pub struct MemUart {
    char buf[64];
    int len;
} use Uart;

impl Uart for MemUart {
    int send(char *b, int n) {
        int i;
        if (n < 0 || self->len + n > 64) return -1;
        i = 0;
        while (i < n) {
            self->buf[self->len + i] = b[i];
            i = i + 1;
        }
        self->len = self->len + n;
        return n;
    }

    int recv(char *b, int n) {
        int i;
        i = 0;
        while (i < self->len && i < n) {
            b[i] = self->buf[i];
            i = i + 1;
        }
        return i;
    }
}
```

`main.ct`（同时演示依赖注入：`emit` 只接收 `Uart`）：

```ct
#include <stdio.h>

import hal::Uart;
import MemUart;

void emit(Uart u, char *msg, int len) {
    u.send(msg, len);
}

int main(void) {
    MemUart m = { .len = 0 };
    Uart u = m;
    char out[8];
    int n;

    emit(u, "ab", 2);
    emit(u, "cde", 3);

    n = u.recv(out, 8);
    out[n] = 0;
    printf("n=%d text=%s\n", n, out);
    return 0;
}
```

预期输出：

```text
n=5 text=abcde
```

### 6.3 同一程序里混用两个后端

三个 trait 彼此独立，可以各自选不同实现。沿用 6.2 的 `MemUart.h.ct`，再加一个只统计字节数的 `Log`。`CountLog.h.ct`：

```ct
import hal::Log;

pub struct CountLog {
    int bytes;
} use Log;

impl Log for CountLog {
    int write(char *buf, int len) {
        if (len < 0) return -1;
        (void)buf;
        self->bytes = self->bytes + len;
        return len;
    }
}
```

`main.ct`：

```ct
#include <stdio.h>

import hal::Uart;
import hal::Log;
import MemUart;
import CountLog;

int main(void) {
    MemUart m = { .len = 0 };
    CountLog l = { .bytes = 0 };
    Uart u = m;
    Log g = l;

    u.send("hello\n", 6);
    g.write("warn\n", 5);
    printf("mem=%d log=%d\n", m.len, l.bytes);
    return 0;
}
```

预期输出：

```text
mem=6 log=5
```

### 6.4 用假时钟做超时测试（链接期整替换）

`hal::Clock` 没有对象，测试不能注入“假时钟实例”；能做的只有整替换：在测试入口定义同签名的 `hal_platform_now_ms`，让所有 `hal::Clock.nowMs()` 都落到它上面。

```ct
#include <stdio.h>
import hal::Clock;

int fake_t = 0;

int hal_platform_now_ms(void)
{
    fake_t = fake_t + 100;
    return fake_t;
}

int wait_event(int timeout_ms)
{
    int start = hal::Clock.nowMs();
    while (hal::Clock.nowMs() - start < timeout_ms) {
        /* 轮询硬件……这里用固定步进的假时钟模拟 */
    }
    return -1;
}

int main(void)
{
    int rc = wait_event(300);
    printf("timeout rc=%d now=%d\n", rc, fake_t);
    return 0;
}
```

预期输出：

```text
timeout rc=-1 now=400
```

边界必须记住：

- 同一二进制只能有一个时钟。符号是全局的，不能同时存在“快时钟”和“慢时钟”。
- 不能运行时切换：没有构造、没有句柄、没有虚表，替换发生在链接期。
- 不能与 `hal-posix` 的时钟同时存在：它也定义 `hal_platform_now_ms`，两边都定义会得到 `duplicate symbol`。
- 替身放在测试入口，不要放进被测库单元，否则库会自带一份假的全局时钟。

如果需要多时钟或运行期注入，请在应用里自建 `MyClock` trait，`hal` 故意不提供。

## 7. 排错

### `error: 'import' is not supported in compile mode`

```text
examples/fake-uart/FakeUart.h.ct:11:1: error: 'import' is not supported in compile mode
```

原因：`ct check` 只支持单文件、无 import 的检查，任何带 `import` 的单元都会失败。

改法：多单元代码用 `ct build`。

### 跨单元装箱失败：`use of undeclared identifier 'NotPub_hal_Uart_vtable'`

```text
main.ct:6:57: error: use of undeclared identifier 'NotPub_hal_Uart_vtable'
main.ct:6:19: error: variable has incomplete type 'struct NotPub'
```

原因：实现 struct 没有标 `pub`，虚表仍是 `static`，其他单元看不到。

改法：把实现 struct 标成 `pub`。`hal` 的 trait 声明本来就是 `pub`。

### `error: a static trait has no interface value`

原因：试图把 `Clock` 当接口类型使用（声明变量、装箱或传参）。`Clock` 是 namespace 映射，不是 trait 接口。

改法：直接调用 `hal::Clock.nowMs()`，不要声明 `Clock` 变量。

### `error: use of an undeclared variable`（裸写 `Clock.nowMs()`）

原因：`Clock` 是 namespace 入口，不是 import 进来的类型名。

改法：写全 `hal::Clock.nowMs()`。

### `error: expected a parameter name`（参数写 `hal::Uart`）

原因：参数位置不能写限定名。

改法：import 后直接写 `Uart u`。

### 链接期 `undefined reference to 'hal_platform_now_ms'`

原因：程序调用了 `hal::Clock.nowMs()`，但没有链接任何时钟实现；`hal` 只声明符号，不定义它。

改法：链接 `hal-posix`，或在入口单元自己定义 `int hal_platform_now_ms(void)`（第 6.4 节）。

### 链接期 `duplicate symbol '_hal_platform_now_ms'`

原因：同时定义了两份时钟，例如既链接 `hal-posix`，又在入口放了测试替身。符号是全局的，同一二进制只允许一个定义。

改法：二选一；跑测试时不要链接平台包的时钟实现。

### `ct get hal` 之后什么都没有 / 没有可执行文件

预期行为。`hal` 只有契约。加上 `hal-posix`，或按第 3 节自己实现。

## 8. 术语表（Glossary）

本表只解释三类词：本包特有概念、全仓易混概念（借用 / 所有权、句柄、宿主、映射）、以及正文出现过却没有展开的缩写和英文术语。通用编程词汇不在此列。

| 术语 | 含义 | 本包中的所指 |
| --- | --- | --- |
| `HAL` | Hardware Abstraction Layer，硬件抽象层：用统一接口屏蔽板卡、OS 与驱动的差异。 | 本包 `hal` 就是这一层的契约，只声明接口，不含任何实现。 |
| `UART` | Universal Asynchronous Receiver/Transmitter，通用异步收发器：面向字节的串行端口。 | `Uart.h.ct` 的 `pub trait Uart`，方法为 `send` / `recv`。 |
| `GPIO` | General-Purpose Input/Output，通用输入输出：可按位读写电平的引脚。 | `Gpio.h.ct` 的 `pub trait Gpio`，方法为 `read(int pin)` / `write(int pin, int value)`。 |
| `contract layer`（契约层） | 只规定行为、不提供实现的接口定义层。 | 三个 `pub trait` 与 `Clock.m.ct` 的命名空间入口；`hal` 的全部内容都在这一层。 |
| `platform package`（平台包） | 针对具体 OS 或板卡实现契约的包。 | 本包不提供实现；`hal-posix` 是配套的 POSIX 平台包。 |
| `header-only` | 不产出独立 C 翻译单元、只提供声明或内联内容的形态。 | `hal` 自身没有 `.c` 产物；构建消费者时 trait 单元只有空壳，`Clock.m.ct` 只注入 `hal_platform_now_ms` 的声明。 |
| `pub trait` | 可被其他单元 `import`、并允许外部 `struct` 用 `impl` 实现的 trait。 | `Uart` / `Gpio` / `Log` 三个声明均为 `pub trait`。 |
| `.h.ct` | 发布接口、可被 `import` 的单元后缀。 | `Uart.h.ct`、`Gpio.h.ct`、`Log.h.ct`；带 `impl` 的单元也必须是这个后缀。 |
| `.m.ct` | 映射单元后缀，用 `map trait` 把方法挂到某个宿主上。 | `Clock.m.ct`，本包唯一的映射单元。 |
| `map`（映射） | 把 CT 侧 trait 方法直接绑定到 C 符号或宿主上的声明式写法，不写 `impl`。 | `Clock.m.ct` 的 `map trait Clock for namespace hal`，把 `nowMs` 指向 `hal_platform_now_ms`。 |
| `namespace host`（命名空间宿主） | 方法没有接收者、只能以 `namespace::Type.method()` 限定名调用的宿主。 | `map trait Clock for namespace hal`；调用必须写 `hal::Clock.nowMs()`。 |
| `type host`（类型宿主） | 方法挂在某个类型或实例上、调用时需要接收者的宿主。 | 本包不使用类型宿主；三个 trait 由实现方 `impl` 到自有 `struct`，平台包才把它们映射到 `char *` 或实例上。 |
| `handle`（句柄） | 指向资源或对象的可传递标识，通常需要显式释放。 | `hal` 不定义句柄：trait 值只是借用对象的 `{ self, vt }`，`Clock` 连对象都没有。 |
| `boxing`（装箱） | 把实现 trait 的 `struct` 赋给 trait 变量或参数时，编译器生成 `{ self, vt }` 胖指针的过程。 | `Uart u = f;` 或把 `f` 传给 `Uart` 参数；`Clock` 不能装箱。 |
| `vtable` | 虚表：保存某个 `struct` 对某个 trait 的方法指针表。 | 名称形如 `FakeUart_hal_Uart_vtable`；trait 与 `struct` 都是 `pub` 时才以外部链接发出。 |
| `borrow` | 借用：只在使用期间访问对象或缓冲区，不取得所有权，也不负责释放。 | 接口值借用对象，`hal` 不做引用计数；`send` / `recv` / `write` 的 `char *buf` 只在调用期间借用。 |
| `Drop` | 析构钩子：对象销毁时运行的清理代码。 | 本包不定义 `Drop`；实现方的 `impl Drop` 跨单元是 `static`，其他单元 `delete` 时不会派发（见「限制与未支持」第 6 条）。 |
| `pin` | 引脚编号；GPIO 没有需要 open/close 的内核资源，所以契约用整数编号而不是句柄。 | `Gpio.read(int pin)` / `Gpio.write(int pin, int value)` 只收 `int`；字符串入口 `"gpio<N>"` 不在本包，而在 `hal-posix` 的 `GpioName.m.ct`。 |
| `hal_platform_now_ms` | `hal::Clock.nowMs()` 背后的全局 C 符号。 | `Clock.m.ct` 只声明并映射它；定义由平台包或应用在链接期提供，`hal` 自己不含定义。 |
| `MAX_METHODS` | 编译器对单个 trait 方法数的硬上限。 | 当前值为 `64`；第 65 个方法编译失败（见「限制与未支持」第 3 条）。 |
| `L0` / `ctc` | 冻结的种子编译器及其可执行名，不接受 `namespace` / `import` / `pub` / `ct build`。 | 本包文档在 `ct v0.19.1`（ct-ast）上验证，不使用 `ctc`。 |

## 9. 限制与未支持

1. **完全没有实现。** 只有三个 trait 声明和一个时钟入口；只装 `hal` 不会链接到任何 UART、GPIO、时钟或日志代码，调用 `nowMs()` 还会缺 `hal_platform_now_ms`。
2. **没有设备/板卡类型。** 没有 `Hal`、`Device`、`Board` 之类的聚合类型，只有三个 trait 和静态的 `hal::Clock`。
3. **单 trait 方法上限 64**（`MAX_METHODS 64`），第 65 个方法编译失败。其他硬上限：每单元 `MAX_TRAITS 64`、`MAX_STRUCTS 128`、`MAX_FIELDS 64`、`MAX_FUNCS 256`、`MAX_IMPORTS 32`。L0 规范里的 `MAX_METHOD 32` 是冻结种子编译器的上限，不是当前编译器的。
4. **跨单元派发要求 trait 与 struct 都是 `pub`**，否则虚表为 `static`，消费者装箱在 C 编译阶段失败。
5. **带 `impl` 的单元必须是 `.h.ct`。** 普通 `.ct` 不发布接口，不能被 import。
6. **跨单元 `Drop` 不派发。** `impl Drop` 对声明它的单元是 `static` 的；其他单元 `delete` 时调用的是该单元合成的空 drop，释放堆指针/关闭设备的函数体不会运行。包必须暴露显式的 `close`/`free`，或让真正 delete 的单元自己持有 `impl Drop`。
7. **接口值只借用、不拥有。** 对象先死会产生悬垂；`{0,0}` 派发会崩溃；无向下转型、无空值检查。
8. **`ct check` 拒绝任何带 import 的单元**，只适合单文件检查。
9. **不产出可运行产物。** 构建消费者会得到按单元拆分的 `.c`，其中契约单元只有空壳；`Clock.m.ct` 不生成 `.c`，只注入 `hal_platform_now_ms` 的声明。`hal` 自身没有库也没有可执行文件。
10. **多单元语法需要 ct-ast 编译器**；L0 `ctc` 不接受 `namespace`/`import`/`pub`/`ct build`。
11. **线程安全不在契约内。** 方法是否线程安全由实现方决定；GPIO 状态与时钟符号通常都是进程全局量，需要自己加同步。
12. **`buf` 只在调用期间借用。** 实现不得缓存指针；跨调用保留数据必须自行拷贝。
13. **时钟是进程级单例。** 一个二进制只能有一个 `hal_platform_now_ms` 定义，不能运行时切换，也不能并存两个时钟。
14. **未提供的能力**：中断/回调、异步 I/O、设备枚举与 `open`/`close` 生命周期、错误码规范、超时参数。`hal` 只覆盖同步字节流、引脚电平、单调时钟和诊断输出四件事。

## 10. 版本与变更记录

| 版本 | 状态 | 变更 |
| --- | --- | --- |
| 0.1.0 | 未发布、未打 tag | 初始契约：`Uart`/`Gpio`/`Log` 三个 `pub trait`；`Clock` 从可装箱 trait（`now_ms()`）改为 namespace 入口 `hal::Clock.nowMs()`，由平台符号 `hal_platform_now_ms` 提供实现；教程并入本 README |

- 契约状态：以 `0.1.0` 为当前基线；破坏性变更升到 `0.2.0`。
- 编译器：清单没有 `requires`；本文在 `ct v0.19.1`（ct-ast）上验证。
- 许可：**MIT**，见 [LICENSE](LICENSE)。
