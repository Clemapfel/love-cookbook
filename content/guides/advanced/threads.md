---
title: "Threads"
authors: [clemapfel]
date: 2025-02-19
---

In this chapter, we'll learn how to use **`love.Thread`**. This is not a guide on parallel programming in general, as many things such as [synchronization primitives](<https://en.wikipedia.org/wiki/Synchronization_(computer_science)>) and [thread global scope](<https://en.wikipedia.org/wiki/Thread-local_storage>) are completely absent in LÖVE.

Lua natively does not support threading at all. Because of this, the LÖVE authors have chosen to design threads that come with heavy restrictions when compared to languages such as [C++](<https://cppreference.com/>) or [Julia](<https://docs.julialang.org/en/v1/>). In return, using (and learning to use) LÖVE threads is a a much simpler topic, allowing users with very little or on experience in parallel programming to still achieve relevant performance gains in their games.

# 1.0 What is a Thread?

Every computer has what is called a CPU. This is the physical chip that does all the computation. Modern CPUs have multiple **cores**. We can think of cores as their own separate tiny CPUs, even though they have access to the same RAM and run right next to each other, multi-core CPUs have what is called **[true parallelism](<https://en.wikipedia.org/wiki/Parallel_computing>)**, which means that two computations can happen on the same CPU, on different cores, at literally the same instant in time - they exhibit **[non-concurrency](<https://en.wikipedia.org/wiki/Concurrency_(computer_science)>)**" This is in opposition to **[pseudo parallelism](<https://en.wikipedia.org/wiki/Preemption_(computing)>)**, which any Lua code and Luas native `coroutines` are all an example of. Parallel computing is an incredible deep topic, and if your interest has been peaked by the end of this chapter, know that it can take programmers many months to truly understand and master working with asynchronous code. Hopefully by the end of this chapter, as instead of by the end of this month, we'll be read to utilize threading in LÖVE.

# 1.1 Glossary, Creating a Thread

Fro this point onwards, when we say "thread", we mean a truly asynchronous thread object, created via `love.Thread`. When we say "routine", we mean a non-concurrent program, which Luas `coroutine` does fall into, but for this chapter, not all "routines" are lua coroutines. 

**Threads are asynchronous, routines are synchronous. Threads run non-concurrently, routines run concurrently.** These terms are important to remember.

Let's create a thread and a routine as well and see what happens:

```lua
-- create a thread
local thread = love.thread.newThread([[
    local args = ...
    print("True Thread says: ", ...);
    print("\n")
]])

-- start the read thread
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

Here, we created a `love.Thread` using it's constructor, which either takes a filename or multi-line string as the argument. This thread is idle when created, we have to start it manually using `start`, which can optionally take arguments that are forwarded to the thread and accessible via `...`. Like shown, we provide the string `"hello"` as the argument for the thread. We also create a lua function, which is a routine and **does not** exhibit true concurrency. To "start" it, we simply call the function, providing `"begon"`for the varargs.

The output above is not a typo, that is the actual console output that the above program *can* exhibit. Why is that, and why does it only sometimes happen?

When we run a Lua program, it is ran in what we will call the "main" thread, or **main**. Any other thread we will call a **worker**. All games run in main by default, and any program not using any threads at all still runs in one thread: main. All threads will run non-concurrently, meaning the CPU is capable of performing operations for both main and a worker at the same time. This is why we see the above output. We start a worker `thread`, then call a function in main, `routine`. From this point onwards, the CPU is running through both the routine in main, and the code we gave to `routine`. While main is printing `Fake Thread says: "begone"`, it just so happened that our actual thread `thread` was printing `True Thread says: hello` in the middle of execution main. The two prints became interleaved, resulting in the garbled out.

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
        io.write(name)
    end
]]

local threadA = love.thread.newThread(code)
local threadB = love.thread.newThread(code)

-- start all three threads
local n_calls = 100
threadA:start(n_calls, "A")
threadB:start(n_calls, "B")
```

Running the above program three times, it prints the following, where each run is a separate invokation of the above lua script

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

Clearly both thread exhibit concurrency, as expected, but why is the order different everytime we run the program?

While the CPU *can* run things at exactly the same instance in time, it does not always do so. Which core gets which operations is up to a lot of fancy technology, including the **CPU [scheduler](<https://en.wikipedia.org/wiki/Scheduling_(computing)>)**. This is a component of the chipset which basically does the following task. When given a list of instructions, choose which to run on which core, at what time. On multi-core CPUs, which instruction goes to which core is entirely non-deterministic. We, as programmers, cannot choose and have no way to influence which core which worker runs on. This is one of the main challenges with parallel computing, as it can debugging a nightmare. If your program exhibits a bug 1% of the time you run it, and there is no way to reproduce a certain [order of operations](<https://en.wikipedia.org/wiki/Out-of-order_execution>), the programmer needs to rely on their skill and experience to verify a program will run correctly 100% of the time instead of testing.

## 1.3 Sharing Memory

So far, we let love compile a lua program from a string that is completely self-contained. What happens when we share code?


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
-- load "module.lua"
require "module"
assert(Module ~= nil) -- passes

-- create a thread, load `worker.lua`
local thread = love.thread.newThread("worker.lua")
thread:start()
```

Here, we create a global table `Module` that is supposed to be shared among all files. We then create a thread from its own file, then started it. What will this print?

```
Error in Thread error (Thread: 0x0198dc22eef0)

worker.lua:1: attempt to index global 'Module' (a nil value)
stack traceback:
	worker.lua:1: in main chunk
stack traceback:
	common/error_handler.lua:54: in function 'handler'
	[love "boot.lua"]:479: in function <[love "boot.lua"]:475>
	[C]: in function 'error'
	[love "callbacks.lua"]:212: in function <[love "callbacks.lua"]:211>
	[love "callbacks.lua"]:185: in function <[love "callbacks.lua"]:175>
	[C]: in function 'xpcall'
```

We actually get an error. The code in thread throws because `Module` is undefined. This is one of the major limitations of threads in LÖVE: threads **cannot share memory with main**. More specifically, any object available in mains scope will not be available in the worker. A simple fix may be to manually include the module then

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

Where we used `thread:isRunning` to check if the thread is currently mid-execution, a `love.timer.sleep` to have main do nothing for one frame, then check again if a thread is running. This technique is called a **busy wait** and is not recommend, as it pauses main completely, making it unable to do anything but wait. If we do this in an actual game, it would tank the frame rate. We will learn a much better solution later in this chapter, but for now this is a crude way to wait for the thread to be done.

What will this print?

```
main: initialized module
worker: initialized module
```

We see that this time the strings are not interlaced, so our crude synchronization worked. However, we see that both the worker and main encountered an unitialized module. This means, the global variable `Module` **exists twice**, entirely separately in both mains and the workers scope. This is important to keep in mind, threads do not share memory, they do not share globals, they don't even share included modules. Any two threads, be it two workers, or a worker and main, are **completely separate environments**.

*Nothing* is shared, not even LÖVE modules:

##### `worker.lua`
```lua
print("thread will sleep")
love.timer.sleep(love.math.random()) -- sleep between 0 and 1 seconds
print("thread woke back up")
```
##### `main.lua`
```
love.thread.newThread("worker.lua"):start() -- run the thread

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
> Not all LÖVE modules are available in workers. Most of `love.graphics` and `love.window` is unable to be used. This **includes creating textures, drawing to canvases or to the main window**. Any kind of drawing or window manipulation from within a worker is impossible in LÖVE 12.0 and earlier versions.

---
## 2.0 Channels and Synchronizations

If threads truly had no way to interface with each other, they'd be close to useless. Luckily, LÖVE does provide a mechanism to at least send data back and forth between threads. This is the `Channel`.

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

### 2.0.1 Creating a Named Channel

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

We can retrieve messages using `demand`, which will sleep the current thread (main or a worker) until a message is found and retrieved, or `pop`, which does not sleep the current thread but may return nil if the channel currently has no messages.

In the following code examples, we will add a label to each section which will make it easier to discuss.

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

A blocking call will completely halt execution of that thread. If we do this in main, **our game will completely freeze**, until a message is retrieved. If we do this in a worker, that worker will freeze until a message comes in. The latter does not affect our game or our games framerate, since main and worker are completely separate. For the former, if a response message never comes in, our game could completely lock and the user OS will prompt them to kill it. For reasons like this, working with threads can be dangerous and hard to debug, even in LÖVE.

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
WORKED_E: exits
MAIN_D: receives worker->main
MAIN_E: exits
```

Or any other order, as long as `MAIN_A` comes before `MAIN_B` and `MAIN_C`. And also, separately, `WORKER_A` comes before `WORKER_B`, etc. 

Whlie this is just like our `AABABAB` example above, with the above setup we can guarantee one things: the worker will wait for a message to come in before processing it, and main will wait for a message to come back before processing it. This is called **synchronization**, we made sure both main and worker are on the same page at least at one point in time. `Channel` is the only method for synchronization in LÖVE. Luckily, it is powerful enough to create some semi-sophisticated systems, as we will do in section 3.

## 2.1 Allowed Data Types

One huge limitation on `Channel`s is that the type of data we are allowed to send between a threads is limited in the following way:

Data can only be transmitted if it is a `string`, `boolean`, `number`, a `love.Object`, or `table` that only contain `strings`, `boolean`s, `number`s or `love.Object`s. This means we **cannot send functions**, and we **cannot send tables that contain functions** between threads. This rules out most OOP-based Lua objects. Let's go through some examples to make these rules clearer:

```lua
local channel = love.thread.newChannel()

channel:push("str") -- `string`: allowed
channel:push(1234) -- `number`: allowed
channel:push({}) -- `table`: allowed
channel:push(love.math.newRandomNumberGenerator()) -- `love.Object`: allowed

channel:push(function() return 1234 end) -- DISALLOWED: `function`

channel:push({
    hash = 0x0231,
    native = love.math.newByteData(2048),
    slots = {
        { true },
        { false },
        { true }
    }
})-- table with only `number`, `love.Object`, `boolean`, `table`: allowed)

local object = {}
object.name = "foo"
function object:initialize()  
    -- ...
end
channel:push(object) -- DISALLOWED: table contains `function`
```

Hopefully this will make the rules clearer. It can be any of the plain data types, or a table of any of the pain data types,  or a table of a table of the plain data types, etc.

Let's go through some edge cases that may no immediately be obvious.

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

`push` stripped the object metatable, meaning `getmetatable` returned `nil`, and thus trying to access `__index` throws the above error. **Metatables are stripped upon sending**. Of course, if `object` had any kind of member functions like this

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

Not allowing functions and not sharing any scope with main imposes heavy limitations on the kind of operations we can do using threading. What is it actually good for then? Usage cases of threads include the following:

+ isolating a process, making it impossible to crash main, for example reading a user supplied file, or requesting a resource using https.
+ running a process at a higher refresh rate, for eample 240hz instead of the vsync'd 60hz. This is common for music playback, as workers can run at any refresh rate they want.
+ distributing small tasks on a large number threads, working through them [in parallel](<https://en.wikipedia.org/wiki/Embarrassingly_parallel>).

The latter can give huge performance gains. For example, when loading a large number of image or sound files, we can distribute them among 8 threads, send a message for each file to load, have any of the threads pick up that message and load a file, then send the loaded `SoundData` or `ImageData` (remember that `Image` is in `love.graphics` and can thus **not** be loaded in a worker) back to main. This means we can load data about 8 times faster. If the user has a large cpu and 16 cores, it could be up to 16 times faster, though with higher threads counts there as somewhat diminishing returns. Either way it is a many-fold increase in speed. We will implement this last case as the conclusion to this chapter, as the message passing system using `Channel` we used so far is perfectly suited to implement what is called a [thread pool](<https://en.wikipedia.org/wiki/Thread_pool>) elegantly.

## 3.0 A Practical Example

Our task is the following: we want to create N threads, send a number of requests to these threads to perform an action such as loading data, then send a response back to main. How can we implement this using `love.Thread`? 

First, we need to decide a message formats. It's best to use tables with a `type` field for this. We will have the following message types

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
    ANSWER = "ANSWER_REQUEST" --[[
        type : MessageType,
        path : String
        data : ImageData / SoundData
    ]],
    
    -- worker -> main: error occurred during loading
    ERROR = "ERROR" --[[
        type : MessageType,
        message : String
    ]],
    
    -- main -> worker: request threadpool shut down
    SHUTDOWN = "SHUTDOWN" --[[
        type : MessageType
    ]],
    
    -- worker -> main: shutdown finished
    SHUTDOWN_RESPONSE = "SHUTDOWN_RESPONSE" --[[
        type : MessageType
        success : Boolean
        message : String
    ]]
}

return MessageType
```

Where the comments shows what kind of the format the table will have. For example

```lua
-- main -> worker: request loading of data
REQUEST = "REQUEST" --[[
    type : MessageType
    path : String
]]
```

Means this message will be send from a worker to main, and it has the following format

Is a message like this:

```lua
channel:push({
    type = "REQUEST",
    path = "assets/music.mp3"
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
    
    -- channel: main -> worker
    self.main2worker = love.thread.newChannel()
    
    -- channel: worker -> main
    self.worker2main = love.thread.newChannel()
    
    -- storage for data, will be filled when worker responds
    self.data = {} -- Table<string, ImageData>

    -- create the threads
    for i = 1, count do
        local thread = love.thread.newThread("worker.lua")
        table.insert(self.threads, thread)
    end
    
    -- start the threads, they will idle until a job is received
    for _, thread in ipairs(self.threads) do
        thread:start(
            self.main2worker, 
            self.worker2main
        ) -- forward channels to threads
    end
    
    return self
end

--- @brief request data to be loaded
--- @param path string full path to data file
function ThreadPool:request(path)
    assert(type(path) == "string", "In ThreadPool.requestSoundData: for argument #1: string expected")
    
    self.main2worker:push({
        type = MessageType.REQUESTS,
        path = path,
        datatype = "SoundData"
    })
end

--- @brief
--- @param path string full path to data file
--- @return love.Data? may be nil if data is not yet read
function ThreadPool:get(path)
    assert(type(path) == "string", "In ThreadPool.get: for argument #1: string expected")
    return self.data[path] -- may be nil if not yet read
end

--- @brief
function ThreadPool:update(delta)
    -- work through all received messages
    while self.worker2main:getCount() > 0 do
        
    end 
```







