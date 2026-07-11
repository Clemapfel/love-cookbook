---
title: "Threads"
authors: [clemapfel]
date: 2025-02-19
---

In this chapter, we'll learn how to use **`love.Thread`**. This is not a guide on parallel programming in general, it is only specific to LÖVE asynchronous programming. This guide applies to LÖVE v11.0 or newer.

## Table of Contents

- [1.0 What is a Thread?](#10-what-is-a-thread)
- [1.1 Glossary, Creating a Thread](#11-glossary-creating-a-thread)
- [1.2 Scheduling](#12-scheduling)
- [1.3 Sharing Memory](#13-sharing-memory)
- [2.0 Channels and Synchronizations](#20-channels-and-synchronizations)
    - [2.0.1 Creating an Unnamed Channel](#201-creating-an-unnamed-channel)
    - [2.0.2 Creating a Named Channel](#202-creating-a-named-channel)
- [2.1 Transmitting Data](#21-transmitting-data)
- [2.2 Allowed Data Types](#22-allowed-data-types)
- [3.0 A Practical Example](#30-a-practical-example)
- [4.0 Addendum](#40-addendum)
    - [4.1 Using a Channel as Semaphore](#41-using-a-channel-as-semaphore)
    - [4.2 Sharing FFI Memory](#42-sharing-ffi-memory)

Lua natively does not support threading at all. Despite this, the LÖVE authors have implemented threads, which can be vital for modern game engines, though they come with heavy restrictions when compared to languages such as [C++](<https://cppreference.com/>) or [Julia](<https://docs.julialang.org/en/v1/>). In return, however, using (and learning to use) LÖVE threads is a much simpler topic than in those languages, allowing users with very little or no experience in parallel programming to still achieve relevant performance gains in their games.

---

# 1.0 What is a Thread?

Every computer has what is called a CPU, which is the physical chip that does all the computation. Modern CPUs have multiple **cores**. We can think of cores as their own separate tiny CPUs, even though they have access to the same RAM and run right next to each other, multi-core CPUs exhibit **[true parallelism](<https://en.wikipedia.org/wiki/Parallel_computing>)**, which means that two computations can happen on the same CPU, on different cores, at literally the same instant in time. Programs running on multiple cores at once are called **[non-concurrenct](<https://en.wikipedia.org/wiki/Concurrency_(computer_science)>)**. This is in opposition to **[concurrency, or pseudo-parallelism](<https://en.wikipedia.org/wiki/Preemption_(computing)>)**, which is what normal Lua code (and Luas native `coroutines`) are. We only need LÖVE if we want true parallelism.

# 1.1 Glossary, Creating a Thread

From this point onward, when we say "thread", we mean a truly asynchronous thread object, created via `love.Thread`. When we say "routine", we mean a a non-concurrently running program, which Lua's `coroutine` does fall into, but for this chapter, not all "routines" are lua coroutines.

**Threads are asynchronous, routines are synchronous. Threads run concurrently, routines run non-concurrently.**

Let's create a thread and a routine and see what happens:

```lua
-- create a thread
local thread = love.thread.newThread([[
    local args = ...
    print("True Thread says: ", ...);
    print("\n")
]])

-- start the  thread
thread:start("hello")

-- create a routine
local routine = function(...)
    local args = ...
    print("Fake Thread says: ", ...);
    print("\n")
end

-- start the routine
routine("begone")
```
```
True Thread says: Fake Thread says: 		begonehello
```

Here, we created a `love.Thread` using its constructor, which either takes a filename or multi-line string as the argument. This thread is idle when created, we have to start it manually using `start`, which can optionally take arguments that are forwarded to the thread and accessible via `...`. Like shown, we provide the string `"hello"` as the argument for the thread. We also create a lua function, then, to "start" it, we simply call the function, providing `"begone"` for the vararg.

The output above is not a typo, that is the actual console output that the above program *can* exhibit. Why is that, and why does it only happen sometimes?

When we run a Lua program, it is ran in what we will call the "main" thread, or **main**. Any other thread we will call a **worker**. All games run in main by default, and any program not using any threads at all still runs in one thread: main. Any two threads will run concurrently to each other, meaning the CPU is capable of performing operations for both main and a worker at the same time, as well as for a worker and worker. However, within the same theads, execution is concurrent. This is why we see the above output. We start a worker, `thread`, then call a function in main, `routine`. From this point onwards, the CPU is running through both `routine` in main and the code of `thread` in a worker **concurrently**. While main is printing `Fake Thread says: "begone"`, it just so happened that our worker `thread` was printing `True Thread says: hello` in the middle of main printing. The two prints became interleaved, resulting in the garbled output.

If you run the above program, most of the time it will behave as expected, printing

```
True Thread says: hello
Fake Thread says: begone
```

Why is that? Let's run another experiment:

## 1.2 Scheduling

```lua
local code = [[
    local n, name = ...
    for i = 1, n do
        io.write(name) -- write to stdout without a newline
    end
]]

local threadA = love.thread.newThread(code)
local threadB = love.thread.newThread(code)

-- start all threads
local n_calls = 100
threadA:start(n_calls, "A") -- print 100 As
threadB:start(n_calls, "B") -- print 100 Bs
```

Running the above program four times, it prints the following, where each run is a separate invocation of the above lua script.

```
AAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBB
```
```
AAAAAAAAAAAAAAABABAABBBABABBBBBBBBBBBBBB
```
```
ABABABABBAAABBABBABBBABBABABABAAAAAAABBB
```
```
BBBBBBBBBBBBBBBBBBBBAAAAAAAAAAAAAAAAAAAA
```

Clearly both threads exhibit concurrency, as expected, but why is the order different every time we run the program?

While the CPU *can* run things at exactly the same instance in time, it does not always do so. Which core gets which operations is up to a lot of fancy technology, including the **CPU [scheduler](<https://en.wikipedia.org/wiki/Scheduling_(computing)>)**. This is a component of the chipset which basically does the following task: when given a list of instructions, choose which instruction should run on which core, at what time. On multi-core CPUs, which core is chosen for which instruction is entirely non-deterministic. We, as programmers, cannot choose and have no way to influence which core which worker runs on, though a routine within itself will usually run on the same core. This is one of the main challenges with parallel computing, as it can make debugging a nightmare. If your program exhibits a bug 1% of the time you run it, and there is no way to reproduce a certain [order of operations](<https://en.wikipedia.org/wiki/Out-of-order_execution>) to trigger that 1% bug, the programmer needs to rely on their skill, experience, or diligent testing to verify a program will run correctly 100% of the time.

## 1.3 Sharing Memory

So far, we let love compile a lua program from a string that is completely self-contained. What happens when we share code between main and a worker?

##### `module.lua`
```lua
-- create a global module
if Module == nil then Module = {} end
Module.initialized = false

-- add an initialize function
function Module.initialize()
    print("main: initialized module\n")
    Module.initialized = true
end
```
##### `worker.lua`
```lua
if not Module.initialized then
    Module.initialize()
    print("worker: initialized module\n")
else
    print("worker: module already initialized\n")
end
```
##### `main.lua`
```lua
require "module" -- load "module.lua"
assert(Module ~= nil) -- passes

-- create a thread, load `worker.lua`
local thread = love.thread.newThread("worker.lua")
thread:start()
```

Here, we create a global table `Module` that is supposed to be shared among all files. We then create a thread using a file instead of a string this time, then start it.

What will this print?

```
Error in Thread error (Thread: 0x0198dc22eef0)

worker.lua:1: attempt to index global 'Module' (a nil value)
stack traceback:
	worker.lua:1: in main chunk
```

We actually get an error. The code in the worker throws because `Module` is undefined. This is one of the major limitations of threads in LÖVE: threads **cannot share memory with main**. More specifically, any object available in main's scope will not be available in the worker. Some may think that the simple fix is to manually include the module then:

##### `worker.lua`
```lua
require "module" -- include the module in worker scope
if not Module.initialized then
    Module.initialize()
    print("worker: initialized module\n")
else
    print("worker: module already initialized\n")
end
```
##### `main.lua`
```lua
-- create the worker
local thread = love.thread.newThread("worker.lua")

-- start the worker
thread:start()

-- wait for the worker to finish
while true do
    if not thread:isRunning() then
        break
    else
        love.timer.sleep(1 / 60) -- sleep main for 1/60s
    end 
end

assert(thread:isRunning() == false) -- passes, thread is done

require "module" -- include the module in main scope
if not Module.initialized then
    Module.initialize()
    print("main: initialized module\n")
else
    print("main: module already initialized\n")
end
```

Where we used `thread:isRunning` to check if the thread is currently mid-execution, `love.timer.sleep` causes main do nothing for one frame, then check again if a thread is running. This technique is called a [*busy wait*](<https://en.wikipedia.org/wiki/Busy_waiting>) and is not recommended, as it pauses main completely, making it unable to do anything but wait. If we reduce the `sleep` duration, it spikes the CPU core main is running on to 100%, as it checks as often as possible per CPU tick. If we do this in an actual game, it would tank the frame rate. We will learn a much better solution later in this chapter, but for now this is a crude way to wait for the thread to be done.

Anyway, now that we have included the module manually in the worker, will the worker be able to access the module?

```
main: initialized module
worker: initialized module
```

We see that this time the strings are not interlaced, so our crude synchronization worked. However, we see that both the worker and main encountered an uninitialized module. This means, the global variable `Module` **exists twice**, entirely separately in both main's and the worker's scope. Threads do not share memory, they do not share globals, they don't even share included modules. Any two threads, be it two workers, or a worker and main, are **completely separate environments**.

*Nothing* is shared, not even LÖVE modules:

##### `worker.lua`
```lua
print("thread will sleep")
love.timer.sleep(love.math.random()) -- sleep between 0 and 1 seconds
print("thread woke back up")
```
##### `main.lua`
```lua
local thread = love.thread.newThread("worker.lua")
thread:start()

-- wait for the thread to finish
while true do
    if not thread:isRunning() then
        break
    else
        love.timer.sleep(1 / 60)
    end
end
```

Running this, it throws

```
thread will sleep
Error in Thread error (Thread: 0x0249f182f3e0)

worker.lua:2: attempt to index field 'timer' (a nil value)
stack traceback:
```

`love.timer` is not available in `worker.lua`. For any thread other than main, we need to manually include the love modules like this:

```lua
require "love.timer"
require "love.math"

print("thread will sleep")
love.timer.sleep(love.math.random())
print("thread woke back up")
```
```
thread will sleep
thread woke back up
```

Any module other than `love.thread` itself must be included manually in worker scope.

> [!CAUTION]
> Not all LÖVE modules are available in workers. Most of `love.graphics` and `love.window` is unable to be used. This **includes creating textures, drawing to canvases, or to the main window**. Any kind of drawing or window manipulation from within a worker is impossible in LÖVE 12.0 and earlier versions.

---

## 2.0 Channels and Synchronizations

If threads truly had no way to interface with each other, they'd be close to useless. Luckily, LÖVE does provide a mechanism to at least send data back and forth between threads. This is the [`Channel`](<https://love2d.org/wiki/Channel>).

To access a channel from main or a worker, we can either share it using the varargs at the top of the function (cf. Section 1.1), or we can use `love.thread.getChannel`, which creates a new named channel if it does not yet exist, or retrieves it if it does:

### 2.0.1 Creating an Unnamed Channel

###### `main.lua`
```lua
-- create two unnamed channels
local main2worker = love.thread.newChannel()
local worker2main = love.thread.newChannel()

-- create a thread
local worker = love.thread.newThread("worker.lua")

-- transmit the channels using `start`
worker:start(main2worker, worker2main)
```
##### `worker.lua`
```lua
local main2worker, worker2main = ... -- get the two channels from `start`

-- use channels after this point
assert(main2worker:typeOf("Channel") and worker2main:typeOf("Channel"))
```

### 2.0.2 Creating a Named Channel

###### `main.lua`
```lua
-- create two unnamed channels
local main2worker = love.thread.getChannel("main2worker")
local worker2main = love.thread.getChannel("worker2main")

-- create a thread
local worker = love.thread.newThread("worker.lua")
worker:start() -- start called without args this time
```
##### `worker.lua`
```lua
-- retrieve the channels by name
local main2worker = love.thread.getChannel("main2worker")
local worker2main = love.thread.getChannel("worker2main")

-- use channels after this point
assert(main2worker:typeOf("Channel") and worker2main:typeOf("Channel"))
```

## 2.1 Transmitting Data

Now that we have our channels accessible in both main and the worker, we can send data between them using `push`. We will call these pieces of data a "message" for reasons that will become obvious later.

We can retrieve messages using `demand`, which **will sleep the current thread (main or a worker) until a message is found and retrieved**, or `pop`, which **does not sleep** the current thread, but may return nil if the channel currently has no messages.

In the following code examples, we will add a label to each section which will make it easier to discuss:

###### `main.lua`
```lua
-- [MAIN_A] start the main execution
local main2worker = love.thread.getChannel("main2worker")
local worker2main = love.thread.getChannel("worker2main")

local worker = love.thread.newThread("worker.lua")
worker:start()

-- [MAIN_B] send a message from main to worker
main2worker:push("do you copy, over")

-- [MAIN_C] wait to receive a message from the worker
local message = worker2main:demand() -- main will halt execution here

-- [MAIN_D] message arrived, use it
assert(message == "roger")

-- [MAIN_E] exit main
```
##### `worker.lua`
```lua
-- [WORKER_A] start worker execution
local main2worker = love.thread.getChannel("main2worker")
local worker2main = love.thread.getChannel("worker2main")

-- [WORKER_B] wait to receive a message from main to worker
local message = main2worker:demand() -- worker will halt execution here

-- [WORKER_C] message arrived, use it
assert(type(message) == "string")

-- [WORKER_D] send a message from worker to main
worker2main:push("roger")

-- [WORKER_E] exit worker
```
We will trace through this carefully, however we first notice that we have two **blocking calls**, with `demand`.

A blocking call will completely halt execution of that thread. If we do this in main, **our game will completely freeze**, until a message is retrieved. If we do this in a worker, that worker will freeze until a message comes in. The latter does not affect our game or our game's framerate, since main and worker are completely separate. For the former, if a response message never comes in, our game could completely lock up and the user's OS will prompt them to kill the process. For reasons like this, working with threads can be dangerous and hard to debug, even in LÖVE. If we do not want to block the current thread, we can use `pop`, which returns immediately.

This the general program flow:

```
MAIN_A: start main
MAIN_B: send main->worker
MAIN_C: wait for worker->main

WORKER_A: start worker
WORKER_B: wait for main->worker message
WORKER_C: receives main->worker
WORKER_D: send worker->main
WORKED_E: exits

MAIN_D: receives worker->main
MAIN_E: exits
```

While this is how we conceptualize the above program, remember that we cannot guarantee order between threads. The above could run in the following order:

```
MAIN_A: start main
WORKER_A: start worker
WORKER_B: wait for main->worker message
MAIN_B: send main->worker
MAIN_C: wait for worker->main
WORKER_C: receives main->worker
WORKER_D: send worker->main
MAIN_D: receives worker->main
WORKED_E: exits
MAIN_E: exits
```

Or any other permutation, as long as `MAIN_A` comes before `MAIN_B`, and `MAIN_C`. And also, separately, `WORKER_A` comes before `WORKER_B`, etc.

While this is just like our `AABABAB` example above, with the this `demand` setup we can guarantee one thing: the worker will wait for a message to come in before exiting, and main will wait for a message to come back before processing it. With this well-suited and idiomatic **synchronization** we made sure both main and worker are on the same page at least at one point in time. `Channel` is the only method for synchronization in LÖVE. Luckily, it is powerful enough to create some semi-sophisticated systems, as we will do in section 3.

## 2.2 Allowed Data Types

One huge limitation on `Channel`s is that the type of data we are allowed to send between threads is limited in the following way:

Data can only be transmitted if it is a `string`, `boolean`, `number`, a `love.Object`, `nil`, or `table` that only contain `strings`, `boolean`s, `number`s or `love.Object`s. This means we **cannot send functions**, and we **cannot send tables that contain functions** between threads. This rules out most OOP-based Lua objects. Let's go through some examples to make these rules clearer:

```lua
local channel = love.thread.newChannel()

channel:push("str") -- `string`: ALLOWED
channel:push(1234) -- `number`: ALLOWED
channel:push({}) -- `table`: ALLOWED
channel:push(love.math.newRandomNumberGenerator()) -- `love.Object`: ALLOWED
channel:push(nil) -- `nil`: ALLOWED

channel:push(function() return 1234 end) -- DISALLOWED: `function`

channel:push({
    hash = 0x0231,
    native = love.math.newByteData(2048),
    slots = {
        { true },
        { false },
        { true }
    }
})-- table with only `number`, `love.Object`, `boolean`, `table`: ALLOWED)

local object = {}
object.name = "foo"
function object:initialize()  
    -- ...
end
channel:push(object) -- DISALLOWED: table contains `function`
```

Hopefully this elucidates these rules. It can be any of the plain data types, or a table of any of the plain data types, or a table of a table of the plain data types, etc.

Let's go through some edge cases that may not immediately be obvious.

```lua
local thread = love.thread.newThread("worker.lua")
local main2worker = love.thread.newChannel()
local worker2main = love,thread.newChannel()

main2worker:push({
    thread, 
    main2worker, 
    worker2main
}) -- ALLOWED
```

This is allowed, as the table only contains love objects, even if those objects are the thread or channels itself.

##### `main.lua`
```lua
local Type = {}
Type.name = "Type"
function Type:initialize()
    -- ...
end

local object = setmetatable({
    name = "Classic Object"
}, {
    __index = Type
})

print("main says type is ", getmetatable(object).__index)
love.thread.getChannel("main2worker"):push(object)
```

This is the typical paradigm used by lua OOP object system, the `__index` metamethod is set to the type table. Is this allowed?

##### `worker.lua`
```lua
local object = love.thread.getChannel("main2worker"):demand()
print("worker says type is ", getmetatable(object).__index.name)
```
```
Error in Thread error (Thread: 0x01c928a3be70)

worker.lua:2: attempt to index a nil value
```

It is allwoed, but we get a worker-side error. `push` stripped the object metatable, meaning `getmetatable` returned `nil`, and thus trying to access `__index` throws the above error. **Metatables are stripped upon sending**. And even if it was send, `__index` in main points to the global `Type` in main, which does not exist in the worker.

> [!CAUTION]
> Any `love.Object` is sent **by-reference**, so both the main and worker have access to the same cpp-side object. Any other kind of data is sent **by-value**, meaning it will be deep-copied automatically, we can only reference the same objects in both main and any worker if it was created using `new\*` functions provided by a love module.

Of course, if `object` had any kind of member functions like this

```lua
local object = setmetatable({
    name = "Classic Object",
    method = function() -- member function
        -- ...
    end
}, {
    __index = Type
})
```

This is not allowed, as it is a table that contains a function.

Not allowing functions and not sharing any scope with main imposes heavy limitations on the kind of application we can use using threading for. What is it actually good for then? Usage cases of threads include the following:

+ isolating a process, making it impossible to crash main, for example reading a user supplied file, or requesting a resource using https.
+ running a process at a higher refresh rate, for example 240Hz instead of the vsync'd 60Hz. This is common for music playback, as workers can run at any refresh rate they want.
+ distributing a large number of small tasks and working through them [in parallel](<https://en.wikipedia.org/wiki/Embarrassingly_parallel>).

The latter can give huge performance gains. For example, when loading a large number of image or sound files, we can distribute them among 8 threads, by sending a message for each file to load, have any of the threads pick up that message and load a file, then send the loaded `SoundData` or `ImageData` (remember that `Image` is in `love.graphics` and can thus **not** be loaded in a worker) back to main. This means we can load data about 8 times faster. If the user has a big CPU with 16 cores, it could be up to 16 times faster, though with higher thread counts there are somewhat diminishing returns. Either way it is a many-fold increase in speed.

We will implement this last case as the conclusion to this chapter. The message passing system using `Channel` we used so far is perfectly suited to implement what is called a [thread pool](<https://en.wikipedia.org/wiki/Thread_pool>) that achieves this elegantly.

## 3.0 A Practical Example

Our task is the following: we want to create N threads, send a number of requests to these threads, have any thread that is currently unoccupied pick up the tasks, load the data, then send a response back to main to deliver the data. 

First, we need to decide on message formats. It's best to use tables with a `type` field for messages. We will have the following message types

##### `message_type.lua`

```lua
--- @enum MessageTypes
local MessageType = {
    -- main -> worker: request loading of data
    REQUEST = "REQUEST" --[[
        type : MessageType
        path : String
    ]],
    
    -- worker -> main: data loading done, deliver data
    ANSWER = "ANSWER" --[[
        type : MessageType,
        id : Number -- unique thread id
        path : String
        data : ImageData / SoundData
    ]],
    
    -- worker -> main: error occurred during loading
    ERROR = "ERROR" --[[
        type : MessageType,
        id : Number
        error : String
    ]],
    
    -- main -> worker: request threadpool shut down
    SHUTDOWN = "SHUTDOWN" --[[
        type : MessageType
    ]],
    
    -- worker -> main: shutdown finished
    SHUTDOWN_RESPONSE = "SHUTDOWN_RESPONSE" --[[
        type : MessageType
        id : Number
    ]]
}

return MessageType
```

Where the comments show what kind of format the message will have. For example

```lua
-- worker -> main: error occurred during loading
ERROR = "ERROR" --[[
    type : MessageType,
    id : Number
    error : String
]]
```

Means this message will be sent from a worker to main, and it has the following format

```lua
channel:push({
    type = "ERROR",
    id = 32,
    error = "Example Error Message"
})
```

---

With the message formats settled, let's implement the main-side of the thread pool:

#### `thread_pool.lua`
```lua
local MessageType = require "message_type" -- import message type enum
local ThreadPool = {}

--- @brief create a new thread pool
--- @param count number number of threads, optional
function ThreadPool:new(count)
    if count == nil then
        -- if not specified, use as many threads as the user has cores
        count = math.max(1, love.system.getProcessorCount() - 1 )
    end

    assert(type(count) == "number", "In ThreadPool.new: for argument #1: number expected")

    local self = {}

    -- list of threads
    self.threads = {} -- Table<love.Thread>

    -- shared channel: main -> worker
    self.main2worker = love.thread.newChannel()

    -- shared channel: worker -> main
    self.worker2main = love.thread.newChannel()

    -- storage for data, will be filled when worker responds
    self.data = {} -- Table<Path, ImageData>

    -- create the threads
    for i = 1, count do
        local thread = love.thread.newThread("thread_pool_worker.lua")
        table.insert(self.threads, thread)
    end

    -- start the threads, they will idle until a job is received
    for id, thread in ipairs(self.threads) do
        thread:start(
            self.main2worker,
            self.worker2main,
            id -- unique thread id
        ) -- forward channels to threads
    end

    return setmetatable(self, {
        __index = ThreadPool
    }) -- classic OOP idiom
end

--- @brief request data to be loaded
--- @param path string full path to data file
function ThreadPool:request(path)
    assert(type(path) == "string", "In ThreadPool.requestSoundData: for argument #1: string expected")

    self.main2worker:push({
        type = MessageType.REQUEST,
        path = path,
        datatype = "SoundData"
    })
end

--- @brief
--- @param path string full path to data file
--- @return love.Data? may be nil if data is not yet read
function ThreadPool:get(path)
    assert(type(path) == "string", "In ThreadPool.get: for argument #1: string expected")
    return self.data[path] -- may be nil if not yet ready
end

--- @brief work through all received messages this frame
function ThreadPool:update(delta)
    -- while at least one message in is channel, switch on message type
    while self.worker2main:getCount() > 0 do
        -- get the current message
        local message = self.worker2main:pop() -- `pop`, not `demand`, do not stall main
        if type(message) == "table" then
            if message.type == MessageType.ANSWER then
                -- if answer request, log data to be received with `get`
                self.data[message.path] = message.data
            elseif message.type == MessageType.ERROR then
                -- if error, forward error
                print("In ThreadPool.update: thread #" .. message.id .. " errored with " .. message.error .. "\n")
            elseif message.type == MessageType.SHUTDOWN_RESPONSE then
                -- noop
            else
                -- else, malformed message.type or wrong message type for worker -> main
                error("In ThreadPool.update: unhandled message type " .. tostring(message.type))
            end
        else
            error("In ThreadPool.update: unhandled message: message is not a table")
        end
    end
end

return ThreadPool
```

##### `thread_pool_worker.lua`

```lua
-- include shared message types
local MessageType = require "message_type"

-- include necessary love modules
require "love.sound"

-- retrieve channels from thread:start
local main2worker, worker2main, id = ...

-- shutdown mode, once enabled, return if no messages left
local shutdownActive = false

-- infinitely wait for messages until shutdown is received
while not shutdownActive do
    -- get current message
    local message = main2worker:demand() -- blocking wait, okay for workers
    
    -- switch on message type
    if type(message) == "table" then
        if message.type == MessageType.REQUEST then
            -- data request, load data and send back
            local success, error_or_data = pcall(love.sound.newSoundData, message.path)
            if success then
                -- load succeeded: send data
                worker2main:push({
                    type = MessageType.ANSWER,
                    id = id,
                    data = error_or_data,
                    path = message.path
                })
            else
                -- load failed: send error
                worker2main:push({
                    type = MessageType.ERROR,
                    id = id,
                    error = error_or_data
                })
            end
        elseif message.type == MessageType.SHUTDOWN then
            -- thread pool requested shutdown
            shutdownActive = true
        else
            -- unhandled message type, respond with error
            worker2main:push({
                type = MessageType.ERROR,
                id = id,
                error = "Unhandled message type: " .. tostring(message.type)
            })
        end
    else
        worker2main:push({
            type = MessageType.ERROR,
            id = id,
            error = "Message is not a table"
        })
    end
end

-- thread is exiting, send shutdown message
worker2main:push({
    type = MessageType.SHUTDOWN_RESPONSE,
    id = id
})

return
```

Where `pcall` is used to safely call `love.sound.newSoundData`, which could error.

Let's try our thread pool out:

##### `main.lua`
```lua
local ThreadPool = require "thread_pool" -- `thread_pool.lua`

-- instance thread pool
local pool = ThreadPool.new()

-- path to data if loaded, false otherwise
local paths = {
    ["path/to/resource.mp3"] = false,
    ["path/to/other.mp3"] = false,
    -- ...
}

-- request all data, thread pool will slowly work through them
for path, _ in pairs(paths) do
    pool:request(path)
end

love.update = function(dt)
    pool:update() -- handle all received messages this frame

    for path, ready in pairs(paths) do
      -- if not yet loaded
      if ready == false then
            -- check if loading done
            local data = pool:get(path)
            if data ~= nil then
                -- if data is ready, this is sound data
                paths[path] = data
            else
                -- else it is not yet ready
            end
        end
    end
end
```

This is a fully functional thread pool which can crunch through thousands of audio files in seconds, even though it is only about 150 lines, thanks to the limitations and simplicity of `love.Thread` and `love.Channel`. It is easy to extend this thread pool, for example by adding more message types, or by changing the callback of what exactly `"REQUEST"` triggers in `thread_pool_worker.lua`.

Asynchronous programming is an incredibly deep topic, so hopefully we'll have garnered enough knowledge to start exploring more.

---

### 4.0 Addendum

> [!CAUTION]
> The following is for advanced users only, which already know asynchronous programming. It will make no attempts to not be technical.

### 4.1 Using a Channel as Semaphore

```lua
-- in main or worker, we can synchronize for a single function invocation by using a channel like a RAII-style semaphore
local sharedObject = love.image.newImageData( -- ...
local callback = function(shared) 
    -- do atomic operations here
    shared:setPixel(
        4, 2, -- pixel xy 
        1, 0, 1, 1 -- rgba
    )
end

local channel = love.thread.getChannel("imagelock")
channel:performAtomic(callback, sharedObject)
```

### 4.2 Sharing FFI Memory

```lua
-- in main:

-- allocate shared memory
local shared = ffi.new("uint8_t[?]", 1024)

-- send pointer as number, ffi is disallowed
main2worker:send(tonumber(ffi.cast("uint32_t", shared)))

-- main can modify memory (race conditions apply, may crash)
shared[12] = 0x4
```
```lua
-- in worker:

-- retrieve pointer, cast back to shared memory array
local shared = ffi.cast("uint8_t[?]", main2worker:demand())

-- worker can modify memory (race conditions apply, may crash)
shared[12] = 0x5
```

The same can be achieved more safely with LÖVE 12.0's new `ByteData` interface

```lua
-- using luajit ffi
local shared = ffi.new("uint8_t[?]", 1024)
shared[12] = 0x4

-- equivalent to, using love 12.0 ByteData
local shared = love.data.newBytedata(ffi.sizeof("uint8_t") * 1024)
shared:setUInt8(8 * 12, 0x4) -- takes byte offset, not index
```





