---
title: "Filesystem"
authors: [ellraiser]
date: 2025-07-30
---

A common requirement in any game is being able to load and save files to the device.  
LÖVE has a variety of methods available under the `love.filesystem` module that can help you do this.


## Saving Files
LÖVE uses a specific folder for writing files - you can't write to the source folder where your game code is*
Instead, each platform has a special folder where your data will be written to:
- Windows => `%appdata%/LOVE` (`C:\Users\user\AppData\Roaming\LOVE`)  
- MacOS => `/Users/user/Library/Application Support/LOVE/`  
- Linux => `$XDG_DATA_HOME/love/` (`~/.local/share/love/`)  

> [!NOTE]  
> *not yet anyway - in LÖVE 12 you can though!

To view our save folder, we can use the following function to open the path:
```lua
love.system.openURL("file://"..love.filesystem.getSaveDirectory())
```
This will open the save location in your file explorer.

Let's take an example for this chapter to help you understand what you can do with `filesystem`.  

Say we have a game where the player can have multiple file saves or 'slots' for the game, as well as various mods.  
We'll want a generic `settings` file, a folder for our `saves` and a folder for our `mods`.

If you wanted to setup the `saves` or `mods` folder, you can create a directory using {% api "love.filesystem.createDirectory" %}
```lua
local create_saves = love.filesystem.createDirectory('saves')
local create_mods = love.filesystem.createDirectory('mods')
print(create_saves, create_mods) -- will return true if created or already exists
```

To save data, we can use {% api "love.filesystem.write" %} to write to a file:
```lua
local success, err = love.filesystem.write('saves/save1.txt', 'My Save Data!')
if not success then
  print(err) -- if file didn't write successfully
end
```
Note that we specified the `saves/` path here - this means LÖVE will check for a folder called `saves` in the save directory, and if we hadn't already created one it would create it for us!

If we don't specify a path then the file will get written to the root of the save folder instead:
```lua
local success, err = love.filesystem.write('settings.txt', 'Settings File!')
if not success then
  print(err) -- if file didn't write successfully
end
```

One thing to keep in mind is that {% api "love.filesystem.write" %} will wipe the previous contents of the file - if you want to add to a file without clearing the existing data you can use {% api "love.filesystem.append" %} instead:
```lua
love.filesystem.write('somefile.txt', 'Hello ')
love.filesystem.append('somefile.txt', 'World!')
-- file will now contain 'Hello World!'
```

You will have noticed we're setting the file extension simply by putting it as the name of the file to be saved, i.e. `settings.txt` is going to make a `.txt` file.   
LÖVE doesn't care what filename and extension you use with what data you pass in, so it's up to you to make sure that the data you write is valid data for the file you are saving.

This also means you can easily create your own 'fake' format/extensions as LÖVE doesn't actually take the extension into consideration when reading, it always just returns the actual bytes of the file.


## Reading Files
To read back our data we can use {% api "love.filesystem.read" %}:
```lua
love.filesystem.write('saves/save1.txt', 'My Save Data!')
local data, size = love.filesystem.read('saves/save1.txt')
print(data, size) -- will print 'My Save Data!' and 13 (the number of bytes)
```
If the file doesn't exist then `data` will be `nil`, and the `size` variable will instead contain an error message.

You can check if a file exists first using {% api "love.filesystem.exists" %} - this can be useful for checking if a file exists without needing to try reading the whole file, say if you wanted to quickly check what file 'slots' exist for rendering a file select menu.
```lua
local file2_exists = love.filesystem.exists('saves/save2.txt')
if not file2_exists then
  print('no file for slot 2')
end
```

If you wanted to read a directory instead of a file, you can use {% api "love.filesystem.getDirectoryItems" %}.  
For example, we could check the mods folder for any files inside:  
```lua
local mod1 = love.filesystem.write('mods/mod1.lua', 'print("Hello World!")')
local files = love.filesystem.getDirectoryItems('mods')
for f=1, #files do
  print(files[f]) -- will print 'mod1.txt', note: without the /mods/ path!
end
```

If you was running through a large directory with nested folders, you can use {% api "love.filesystem.getInfo" %} to check specific if something is a file, directory, or a symlink:
```lua
function readFiles(path)
  local files = love.filesystem.getDirectoryItems(path)
  for f=1, #files do
    local info = love.filesystem.getInfo(path .. '/' .. files[f]) -- note we need to append the path too
    print(files[f], info.type) -- i.e. 'mod1.lua', 'file'
  end
end
readFiles('mods')
```
If `info.type` was `directory` you could then run the function recursively to list any files in those folders too.

For some files you might want to read the data line by line instead of getting it in one big string - this can be useful for file types such as `.ini` files or `.csv` files, or just for files containing simple lists of data, like highscores.
```lua
-- write some highscores
local highscores = ''
for a=1,10 do
  highscores = highscores .. love.math.random(0, 10000) .. '\n' -- '\n' is a special string that makes a new line or 'return'
end
love.filesystem.write('highscores.txt', highscores)

-- later read them back
for line in love.filesystem.lines('highscores.txt') do
  print(line) -- will give 10 prints, 1 for each score
end
```


## Running Files
Reading files is not the same as running them - if you were to read the contents of one of our 'mod' `.lua` files you'd just get the raw contents back.
```lua
love.filesystem.write('mods/mod1.lua', 'print("Hello World!")')
local data = love.filesystem.read('mods/mod1.lua')
print(data) -- will just print 'print("Hello World!")'
```

If we wanted to run a `.lua` file instead of just reading the raw contents, we can use {% api "love.filesystem.load" %}.

```lua
love.filesystem.write('mods/mod1.lua', 'print("Hello World!")')
local chunk = love.filesystem.load('mods/mod1.lua') -- loads the .lua file but doesn't execute it yet
chunk() -- executes our file, which will then print 'Hello World!'
```

This can be useful for executing mod code, player-written code, or for loading data from your game directly.  

> [!WARNING]
> You should be careful not to directly execute external code without some form of sandboxing or restrictions
> The code you run with love.filesystem.load() has the same access and functional capability as your own
> This could be abused by players in the context of modding code or multiplayer functionality

While you can't write to the source directory where your game code is, {% api "love.filesystem.read" %} is allowed to read from it!  
Using this you can create files that are part of your game's source code, and read them in when the game runs.


## Loading From Source
To read from the source folder you don't need any new methods - {% api "love.filesystem.read" %} is already the one you need!

You can test that by using `love.filesystem.getDirectoryItems('')` and iterating over the result - this will list not only the folders and files in the save directory, but also in the source folder that your `main.lua` is in!
```lua
-- running this will list all items in all folders for both the savedir and the sourcedir
function readFiles(path)
  local files = love.filesystem.getDirectoryItems(path)
  for f=1,#files do
    local info = love.filesystem.getInfo(path .. '/' .. files[f]) -- note we need to append the path too
    print(path .. '/' .. files[f], info.type) -- i.e. 'mod1.lua', 'file'
    if info.type == 'directory' then
      readFiles(files[f])
    end
  end
end
readFiles('')
```

LÖVE will prioritise the save directory over the source one - so if you have a folder called `saves` in both directories and use `love.filesystem.getDirectoryItems('saves')` LÖVE will read the one in the save directory. You should keep this in mind when naming save directory folders vs source directory ones!

A common use for loading files from source is having datafiles for the game as seperate files to make it easier to manage.  
For example say you had a `text.lua` that contained a table with all your text entries inside a `resources` folder in the source directory that looked like this:
```lua
-- resources/text.lua
return {
  name = 'LÖVE',
  type = 'Framework',
  awesome = true
}
```

You can call this in your `main.lua` when the game starts easily enough with {% api "love.filesystem.load" %} to load in the file contents as `.lua`.
```lua
game.g.text = love.filesystem.load('resources/text.lua')() -- note the () right after to execute the loaded chunk
print(game.g.text.name) -- prints 'LÖVE'
```
This will first look for a `resources/text.lua` in the save directory, then if it doesn't find one there it will look for it in the source directory (where it then finds it).


## Other File Formats
`love.filesystem` itself does not provide any functionality for writing specific types of files, like `.json` or `.csv`.
You will need to find third-party libraries to do this, such as [rxi's JSON library](https://github.com/rxi/json.lua).

These libraries are usually straight forward, and simply convert given lua table data into the correct format, which you can then pass straight into {% api "love.filesystem.write" %}.  There are even libraries that let you write a `.lua` table and it's contents directly, meaning you can read/write lua tables without having to convert anything!

For more info on this, see the 'Saving And Loading' chapter later in the cookbook.
