---
title: "Meshes"
authors: [clemapfel]
date: 2026-07-14
---

# Meshes

This chapter will cover **Meshes**, which are a central concept in graphics programming and are used to display any geometry on screen. While rarely used by beginners thanks to LÖVEs high level of abstraction, meshes are actually used internally by LÖVE for displaying any kind of graphics, including for `love.graphics.rectangle`, `love.graphics.circle`, `love.graphics.polygon`, and `draw`ing `Images`, `SpriteBatche`s, `ParticleSystem`s, etc.

By mastering meshes, we can extend LÖVEs graphical capability significantly, rendering shapes not possible with LÖVEs existing high-level API, and achieving performance even better what basic usage of LÖVE can offer.

#### In this chapter we will learn:
+ Why and when to use meshes
+ What vertices, edges, meshes are
+ What vertex attributes, texture coordinates are
+ How to set the mesh draw mode and index buffer
+ How to use meshes to draw tens of thousands of entities at once

---

## Table of Contents

---

# 0. TL;DR: Quick Start

#### [\[click here to skip to section 1 of this chapter\]](#10-what-are-meshes-motivation)

Given here are code snippets that illustrate basic usage of meshes. These are **intended to be referenced after having read this chapter**. Readers new to meshes are not expected to understand these snippets, and should 

### 0.1 Creating a Textured Rectangle

```lua
-- initialization
local x, y, w, h = 50, 50, 200, 300 -- top left xy, width, height
local r, g, b, a = 1, 1, 1, 1 -- color: pure white
local rectangle = love.graphics.newMesh({
        --    x,     y,   u, v,   r, g, b, a
        { 1 + 0, y + 0,   0, 0,   1, 1, 1, 1 },
        { x + w, y + 0,   1, 0,   1, 1, 1, 1 },
        { x + w, y + h,   1, 1,   1, 1, 1, 1 },
        { x + 0, y + h,   0, 1,   1, 1, 1, 1 },
    }, 
    "fan",    -- mesh draw mode
    "dynamic" -- graphics buffer usage
)

local texture = love.graphics.newTexture("assets/toast.jpg")
rectangle:setTexture(texture)

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(rectangle)
end 
```

### 0.2 Creating a Colored Circle

```lua
-- initialization
local x, y, xr, yr = 200, 200, 100, 100 -- center xy, x-radius, y-radius
local vertexCount = 64 -- number of outer vertices
local r, g, b, a = 1, 0, 1, 1 -- color: magenta

local circle -- love.Mesh
do
    local vertices = {}
    local circle_data = {}
    for i = 1, vertexCount do
        local angle = (i - 1) / vertexCount * 2 * math.pi
        table.insert(circle_data, {
            x + math.cos(angle) * xr, -- x
            y + math.sin(angle) * yr, -- y
            math.cos(angle), -- u
            math.sin(angle), -- v
            r, g, b, a
        })
    end

    circle = love.graphics.newMesh(circle_data, "fan", "dynamic")
end

-- drawing
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(circle)
end
```

### 0.3 Creating a Polygon Mesh using Triangulation

```lua
-- input vertex data. format: { x1, y1, x2, y2, ... }
local input = {
--   x,                y
     167.8622990257,   0,
     141.37412207129,  153.70547063563,
    -41.827243725195,  198.73007856213,
    -187.28713855132,  102.30176491128,
    -159.32457952398, -89.182472409685,
    -39.483305587746, -162.49970086587,
     148.0247332512,  -152.10238729167,
}

-- triangulate using loves built-in triangulation, only works for convex polygons
local triangles = love.math.triangulate(input)

-- create the polygon mesh
local polygon -- love.Mesh
do
    -- get bounding box for texture coordinate calculation
    local xMin, yMin = math.huge, math.huge
    local xMax, yMax = -math.huge, -math.huge
    for i = 1, #input, 2 do
        local x = input[i + 0]
        local y = input[i + 1]
        xMin = math.min(xMin, x)
        yMin = math.min(yMin, y)
        xMax = math.max(xMax, x)
        yMax = math.max(yMax, y)
    end
    
    -- convert vertex position to texture coordinate
    local xy2uv = function(x, y)
        return (x - xMin) / (xMax - xMin),
        (y - yMin) / (yMax - yMin)
    end
    
    local vertex_data = {}
    local r, g, b, a = 1, 1, 1, 1
    
    -- iterate each vertex of each triangle, and add it as a mesh vertex
    for _, triangle in ipairs(triangles) do
        -- `triangles` format: {{ x1, y1, ...}, {x1, y1 ...}, ... }
        for i = 1, #triangle, 2 do
            -- `triangle` format: { x1, y1, x2, y2, x3, y3 }
            local x = triangle[i + 0]
            local y = triangle[i + 1]
            local u, v = xy2uv(x, y)
            table.insert(vertex_data, {
                x, y, u, v, r, g, b, a
            })
        end
    end
    
    -- initialize the mesh
    polygon = love.graphics.newMesh(vertex_data, "triangles", "dynamic")
end 

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(polygon)
end
```

### 0.4 Drawing 20k Sprites using Geometry Instancing
###### `main.lua`
```lua
local instanceCount = 20e3 -- we will be drawing *twenty thousand* sprites at >60fps

-- describe instanced mesh format
local instanceMeshFormat = {
    -- instance mesh attribute #1: vertex position
    {
        location = 0,            -- 0-based, for use in shader
        name = "VertexPosition", -- CPU-side name, for use in attachAttribute
        format = "floatvec2"     -- GPU-side data type
    },

    -- instance mesh attribute #2: texture coordinates
    { location = 1, name = "VertexTextureCoords", format = "floatvec2" },
    
    -- instance mesh attribute #3: vertex color
    { location = 2, name = "VertexColor", format = "floatvec4" }
}

-- create instance mesh, quad whose vertices are at x = { -1, 1 }, y = { -1, 1 }
local x, y, w, h = -1, -1, 2, 2
local instanceMesh = love.graphics.newMesh(instanceMeshFormat, {
        -- VertexPosition  | VertexTextureCoords |  VertexColor
        --    x,     y,          u,     v,          r, g, b, a
        { x + 0, y + 0,          0,     0,          1, 1, 1, 1 },
        { x + w, y + 0,          1,     0,          1, 1, 1, 1 },
        { x + w, y + h,          1,     1,          1, 1, 1, 1 },
        { x + 0, y + h,          0,     1,          1, 1, 1, 1 },
    }, 
    "fan",    -- draw mode "fan" for basic quad geometry
    "static"  -- graphics buffer use "static", instanceMesh never changes
)

-- assign the texture
local texture = love.graphics.newTexture("assets/toast.png")
instanceMesh:setTexture(texture)

-- describe data mesh format, this will hold the information for each instance
local dataMeshFormat = {
    {
        location = 3,            -- number of attributes in instanceMeshFormat + 1
        name = "InstanceOffset", -- CPU-side name
        format = "floatvec2"     -- x: offset (in px), y: offset (in px)
    },
    { 
        location = 4,           
        name = "InstanceScale", 
        format = "float"        -- x: scale (in px)
    }
}

-- create the data mesh vertex data
local dataMeshData = {}
local xMin, yMin, xMax, yMax = 50, 50, love.graphics.getWidth() - 50, love.graphics.getHeight() - 50
local scaleMin, scaleMax = 20, 50
for i = 1, instanceCount do
    local offsetX = love.math.random(xMin, xMax)
    local offsetY = love.math.random(yMin, yMax)
    local scale = love.math.random(scaleMin, scaleMax)
    table.insert(dataMeshData, {
        -- InstanceOffset    | InstanceScale
        --       x,       y,   x
           offsetX, offsetY,   scale
    })
end

local dataMesh = love.graphics.newMesh(
    dataMeshFormat,   -- vertex format
    dataMeshData,     -- vertex data
    "points",  -- draw mode (unused)
    "stream"   -- graphics buffer usage: changes every frame
)

-- attach the attributes of dataMesh to instanceMesh
instanceMesh:attachAttribute("InstanceOffset", dataMesh, "perinstance")
instanceMesh:attachAttribute("InstanceScale", dataMesh, "perinstance")

-- set up a draw shader
local instanceShader = love.graphics.newShader("instance_draw.glsl")
-- cf. below for `instance_draw.glsl`

love.draw = function()
    -- set color (`ConstantColor` in vertex shader)
    love.graphics.setColor(1, 1, 1, 1)

    -- bind the shader
    love.graphics.setShader(instanceShader)

    -- bind `instanceTexture` uniform in fragment shader
    instanceShader:send("InstanceTexture", instanceMesh:getTexture())

    -- draw `instanceCount` many copies of `instanceMesh`, with vertex properties queried from `dataMesh`
    love.graphics.drawInstanced(instanceMesh, instanceCount)

    -- unbind shader
    love.graphics.setShader(nil)

    -- print FPS
    love.graphics.print(love.timer.getFPS(), 20, 20)
end

local interpolate = function(lower, upper, ratio)
    return lower * (1 - ratio) + upper * ratio
end

love.update = function(delta)
    -- modify the scales of all instances every frame
    for i, data in ipairs(dataMeshData) do
        -- for each **instance**, get a unique value in [0, 1]
        data[3] = interpolate( -- assign to dataMesh attribute #2: scale
            scaleMin, scaleMax, 
            (math.sin(love.timer.getTime() + i) / 2) + 1 
        )
    end

    -- upload the data to the attached mesh
    dataMesh:setVertices(dataMeshData)
end
```
##### `instance_draw.glsl`
```glsl
#ifdef VERTEX // vertex shader

// instance mesh attributes
layout (location = 0) in vec2 VertexPosition;      // attribute #1: x: position (px), y: position (px)
layout (location = 1) in vec2 VertexTextureCoords; // attribute #2: x: u, y: v
layout (location = 2) in vec4 VertexColor;         // attribute #3: rgba

// data mesh attributes
layout (location = 3) in vec2 InstanceOffset;  // attribute #1: x: offset (px), y: offset (px)
layout (location = 4) in float InstanceScale;  // attribute #2: x: scale

out vec2 FragmentTextureCoords; // final interpolated texture coordinates, for fragment shader
out vec4 FragmentColor;         // final interpolated color, for fragment shader

void vertexmain() { // custom vertex shader entry point
    
    // compute position from custom vertex attributes
    vec2 position = VertexPosition;
    position.xy *= InstanceScale;
    position.xy += InstanceOffset;

    // set texture coords to default value
    FragmentTextureCoords = VertexTextureCoords; // xy = uv

    // set color to default value
    FragmentColor = ConstantColor * VertexColor; // rgba
    // where `ConstantColor` is a hardcoded global that holds the `love.graphics` Color

    // set position
    love_Position = TransformProjectionMatrix * vec4(position.xy, 0.0, 1.0);
    // where `TransformProjectionMatrix` is a hardcoded global that holds the `love.graphics` Transform
    // and `love_Position` is a hardcoded global variable that holds the position of a vertex, in px
}

#endif

#ifdef PIXEL // fragment shader

uniform sampler2D InstanceTexture; // texture of the instance mesh
in vec2 FragmentTextureCoords;     // texture coords from vertex shader
in vec4 FragmentColor;             // color from vertex shader

out vec4 FinalColor; // final fragment color drawn to the screen at love_Position

void pixelmain() { // custom fragment shader entry point
    
    // default behavior of `effect`, implemented manually
    FinalColor = FragmentColor * texture(InstanceTexture, FragmentTextureCoords);
}

#endif
```

---

# 1.0 What Are Meshes? Motivation

Scrolling past the code snippets in section 0, meshes can seem quite intimidating both from a conceptual and implementation side. Before diving into this topic, we may want to first answer the question of why and when we would want to use meshes at all? What are situations where we *have* to use meshes, situations where no other LÖVE API can achieve a certain result.

### 1.0.1 Drawing Custom Shapes

The `love.graphics` shape drawing API has certain limitation, for example, there is no way to draw an **Annulus** (known as a "ring" or "donut" in common language).

![](/assets/img/meshes/annulus_rainbow.png)

This image uses only a single mesh to achieve both the rainbow gradient, and the circular shape with a hole in the middle, and therefore requires only a single performant draw call.

`love.graphics` also does not allow shapes to have more than one color or to draw a textured shape that is not a rectangle. These shapes are only achievable with `love.Mesh`.

### 1.0.2 Texture Deformation

The indie game ["Who's Lila"](<https://store.steampowered.com/app/1697700/Whos_Lila/>) has a mechanic where a picture of the players face is displayed on screen, and the player is tasked to drag certain parts of the face to manually create a certain facial expressions. 

![](/assets/img/meshes/whos_lila.gif)

*(Source: [IndieDB](<https://www.indiedb.com/games/whos-lila>), Copyright: [Garage Heathen](<https://store.steampowered.com/developer/GarageHeathen>))*

Reproducing this mechanic in LÖVE is perfectly possible, and would require nothing but meshes. Achieving this with any other technique would be impractical.

### 1.0.3 Rendering Tens of Thousands of the same Shape

While 3D in this example, a technique that could be used to render tens of thousands of blades of grass in games like "Breath of the Wild" is a graphical capability of most modern GPUs called *geometry instancing*. This technology is available in LÖVE, and LÖVE could match Nintendos custom engine capabilities at least in this specific instance of drawing the same shape, slightly altered, tens of thousands of times. This works exactly the same in both 3D and 2D.

![](/assets/img/meshes/botw_grass.png)

*(Source: [Nintendo Eshop](<https://www.nintendo.com/us/store/products/the-legend-of-zelda-breath-of-the-wild-switch/>), Copyright: Nintendo)*

## 1.1 Glossary: Vertices, Edges, Tris, Meshes

With us now hopefully motivated to put in the effort to understand meshes in order to unlock unlimited and highly advanced graphical capabilities in LÖVE, we will turn our attention to terminology. While this chapter will avoid math such as differential geometry as much as possible, certain terms are unavoidable when speaking about meshes in a technical sense.

A **vertex** (plural: *vertices*) is a point in space (2D or 3D). It has an x coordinate and y coordinate (and z in 3D), as well as a number of other properties, such as a color (encoded as four numbers, red, green, blue, opacity).

Given *exactly two vertices*, an **edge** is a straight line drawn from the first vertices position to the second. An edge is unordered, meaning the edge from vertex A to B is the same object as an edge from B to A. 

Given *exactly three vertices*, a **tri** is the triangle that is defined by these 3 points. This is sometimes called a *face* in math, but *tri* is more common when talking about it in relation to graphics programming and gamedev.

A **mesh**, then, is a collection of one or more tris. Note that these tris do not need to be connected, though they can be. Since vertices can be 2D or 3D, tris, too, can be 2D or 3D, but any property other than the number of coordinates for the position transfers and there is no difference between 2D and 3D for our purposes. 

In LÖVE, unless otherwise specified, vertices have the following properties (where we will explain what uv coordinates are in a later section):

+ **position**: two numbers for the x-coordinate and y-coordinate, in pixels
+ **texture coordinates**: two numbers for the u-coordinate and v-coordinate, each normalized to the value range `[0, 1]`
+ **color**: four numbers, one for the r, g, b, and a (alpha / opacity), each normalized to the value range `[0, 1]`

These properties are stored inline, meaning a vertex with this **vertex format** (position, texture coordinate, color) is a flat table of numbers like so:

```lua
local vertex = { 
    200.5, 300, -- x, y
    0.3, 0.4, -- u, v
    1, 0, 1, 0.5 -- r, g, b, a
}
```

A tri, then, is a table of three vertices:

```lua
local tri = {
    { -- vertex #1
        45, 170,  -- xy: position is (45, 170)
        0.0, 0.0, -- uv: texture coordinate is (0, 0)
        1.0, 0.0, 0.0, 1.0 -- rgba: color is red
    },
    { -- vertex #2
        210, 45, 
        1.0, 0.0, 
        0.0, 1.0, 0.0, 1.0 -- color is blue
    },
    { -- vertex #3
        200, 235, 
        0.5, 1.0, 
        0.0, 0.0, 1.0, 1.0 -- color is green
    },
}
```

A table that contains three or more vertices, defining one or more tris, will also be called the **vertex data** of a mesh. 

Now that we have a tri, we can finally draw our first mesh. Recall that a mesh is a collection of tris, so one tri still counts as a mesh.

We use `love.graphics.newMesh` to create a mesh, and `love.graphics.draw` to draw it. It reacts to `setColor` as does any other `love.graphics` shape. We will not touch on the last two parameters for this function for now, they will be explained in a later section:

```lua
local tri = {
    { 45,  170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- vertex #1: xy uv red
    { 210,  45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- vertex #2: xy uv green
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 },  -- vertex #3: xy uv blue
}

local mesh = love.graphics.newMesh(
    tri, -- vertex data
    "triangles", "dynamic" -- explained in later section
)

love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
end
```

![](/assets/img/meshes/tri_hello_world.png)

Before we analyze this image, let's add another vertex first:

```lua
local tri = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv red
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2: xy uv green
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv blue
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4: xy uv magenta (NEW)
}

local mesh = love.graphics.newMesh(tri, "triangles", "dynamic")

love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
end
```

![](/assets/img/meshes/quad_hello_world.png)

Two question arise: 
+ (i) Why do *four* vertices result in a valid mesh, when meshes are collection of triangles, and each triangle is exaclty three vertices?
+ (ii) Why is the mesh colored like that? Why do we see a smooth mix of colors?

Turning our attention to (i) first, we can use one of LÖVEs rarely used API to answer this question. `love.graphics.setWireframe` makes any mesh draw call after display the *edges* instead of the triangles themself. This function should only used for debugging, not to display meshes in a shipped game.

```lua
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setWireframe(true)
    love.graphics.draw(mesh)
    love.graphics.setWireframe(false)
end
```

![](/assets/img/meshes/quad_hello_world_wireframe.png)

This confirms that the mesh is actually made up out of two valid triangles, so our definition of a mesh being a collection of triangles is still correct. We notice that the two triangles share an edge. This is a key observation. Indeed, we can reproduce the above shape like so:

```lua
--[[
before:
local tri = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv green
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2: xy uv blue
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv red
}

local mesh = love.graphics.newMesh(tri, 
    "fan",
    "dynamic"
)
]]

-- now:
local tri = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv green
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2: xy uv blue
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv red
    
    -- duplicate edge: 1 -> 3
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv green
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv red
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4: xy uv magenta
} 

local mesh = love.graphics.newMesh(tri, "triangles", "dynamic")

love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setWireframe(true)
    love.graphics.draw(mesh)
    love.graphics.setWireframe(false)
end
```

![](/assets/img/meshes/quad_hello_world_wireframe.png)

Where we changed the second argument of mesh from `fan` to  `triangles`. We see that duplicating the shared edge manually results in the exact same shape. So what is `fan` and `triangles` exaclty?

## 1.2 Mesh Draw Modes

The second argument of `love.graphics.newMesh` is called the **draw mode**, which is a value of the enum [`love.MeshDrawMode`](https://love2d.org/wiki/MeshDrawMode). The draw mode determines how the list of vertices in the vertex data is treated when constructing the list of tris internally. It's best to visualize this process. We first meet our two example meshes for this section.

A **heptagon**, a 7-sided regular polygon:

![](/assets/img/meshes/draw_mode_heptagon_base.png)

And a **ribbon**, a connected strip of tris:

![](/assets/img/meshes/draw_mode_ribbon_base.png)

We first take a moment to analyze the vertex layout of these, as they are quite complex shapes.

Firstly, the **heptagon** has 8 vertices, 1 center vertex and 7 for each of it's side. The **center vertex is the first vertex**, the outer vertices are ordered clockwise.

Secondly, the **ribbon** also has 8 vertices. The First vertex is at the bottom left, the second is on the opposite the first, then we move one segment up, with 3rd on the left, 4th on the right, 5th on left, and so on.

Ignoring the math to generate these shapes, how are they drawn? Assuming we already have the vertex data `heptagonData` and `ribbonData`, the above meshes are created as such:

```lua
local heptagonMesh = love.graphics.newMesh(
    heptagonData, -- vertex data
    "fan",        -- draw mode
    "dynamic"     -- buffer usage (ignored for now)
)
local ribbonMesh = love.graphics.newMesh(
    ribbonData,   -- vertex data
    "strip",      -- draw mode
    "dynamic"
)
```

We see that unlike before, the second argument is no longer `triangles`, but `fan` for the heptagon and `strip` for the ribbon. What does this mean?

When the GPU constructs the triangles from the vertex data, it internally constructs a list of indices, then goes through them and groups any 3 as a tri. For example, given indices `i1, i2, i3, ..., k`, where `k` is the number of vertices in the list:

```lua
-- vertex indices
{ i1, i2, i3, i4, i5, i6, i7, ..., k-2, k-1, k }

-- triangle list
{ i1, i2, i3 }, { i4, i5, i6}, ..., { k-2, k-1, k }
```
Where each table `{ a, b, c }` is the triangle with the coordinates `ax, ay, bx, by, cx, cy`.

This is the intuitive thing to do, take each triplet of indices, and that is a tri. This is how exactly how the draw mode `"triangles"` works internally.

Draw mode `fan`, the draw mode used for our heptagon, groups indices as follows:

```lua
-- vertex indices
{ i1, i2, i3, i4, i5, i6, i7, ..., k-2, k-1, k }

-- triangle list
{ i1, i2, i3 }, { i1, i3, i4 }, { i1, i5, i6 }, ... { i1, k-2, k-1}, { i1, k-1, k }
```

We see that each triangle is constructed as follows: the first vertex of the current tri **is the first vertex in the vertex data**. Looking at our heptagon again, we can see this clearly on the right:

![](/assets/img/meshes/draw_mode_heptagon_base.png)

Each triangle shares the the first vertex `i1`. The first tri is `1, 2, 3`, the second is `1, 3, 4`, etc. 

Turning our attention to our ribbon now, it was created using draw mode `"strip"`, which groups indices as follows:

```lua
-- vertex indices
{ i1, i2, i3, i4, i5, i6, i7, ..., k-2, k-1, k } 

-- triangle list
{ i1, i2, i3 }, { i2, i3, i4 }, { i3, i4, i5 }, ... { k-3, k-2, k-1}, { k-2, k-1, k }
```

We see that now, instead of sharing the first vertex, each triangle shares the **last two vertices of the triangle before**. Looking at our ribbon mesh again:

![](/assets/img/meshes/draw_mode_ribbon_base.png)

We can see how the first tri is `1, 2, 3`, the second is `2, 3, 4`, and so on.

With this, we have learned the three draw modes, `"triangles"`, `"fan"`, and `"strip"`. Just for fun, what happens if use the wrong draw mode?

```lua
local heptagonMesh = love.graphics.newMesh(
    heptagonData, 
    "strip",  -- was: "fan"
    "dynamic"
)
```

![](/assets/img/meshes/draw_mode_heptagon_strip.png)

```lua
local heptagonMesh = love.graphics.newMesh(
    heptagonData, 
    "triangles", -- was: "fan"
    "dynamic"
)
```

![](/assets/img/meshes/draw_mode_heptagon_triangles.png)

```lua
local ribbonMesh = love.graphics.newMesh(
    ribbonData, -- vertex data
    "fan",      -- was: "strip"
    "dynamic"
)
```

![](/assets/img/meshes/draw_mode_ribbon_fan.png)

```lua
local ribbonMesh = love.graphics.newMesh(
    ribbonData, -- vertex data
    "triangles",      -- was: "strip"
    "dynamic"
)
```

![](/assets/img/meshes/draw_mode_ribbon_triangles.png)

As an exercise, let's try to understad *how* the mesh was corrupted exactly. We consider the last example, drawing the ribbon with `"triangles"` instead of `"strip"`:

We see that instead of the full ribbon, we only see two triangles. Why is this? We recall that `"triangles"` just goes through the list of vertices and groups them by a group of three. So the first triangle is `1, 2, 3`, the second is `4, 5, 6`, and the last one would be `7, 8, 9`, but our ribbon only has 8 vertices. The GPU handles this without an error, and simply does not draw the last triangle.

This corrupted mesh also shows well that **tris do not need to be connected**. We can have a mesh of complete separate triangles without any issues.

## 1.3 Index Buffers / Vertex map

In our exploration of draw modes, we have use vertex indices `i1, i2, i3` instead of vertex coordinates `x1, y1, x2, y2, x3, y3`. The main reason the GPU and thus LÖVE deals in vertex indices is because of something called an **index buffer** (also called a **Vertex Map**). Each mesh has this buffer internally, it is a table of the form

```lua
{ ia, ib, ic, id, ... }
```

Where `ia`, `ib`, etc. are vertex indices, so numbers between `1` and `k`, the total number of vertices which is also the size of the table of vertex data (since it is a table of tables).

We use `ia`, `ib` here instead of `i1`, `i2` because the index buffer can crucially be **unordered**. For example the following is a perfectly valid index buffer, as long as the mesh has 4 or more vertices:

```lua
{ 1, 3, 2, 3, 1, 4, 4, 2, 3 }
```

Not only is the index buffer unordered, but **vertex indices are allowed to be duplicated**. When the GPU constructs the tris using the draw mode, it goes through each index in the index buffer as described above, and groups the as tris. This allows us to use certain vertices multiple times. While this is great for memory usage, it most importantly interacts with draw mode, allowing us to create well-formed meshes from any vertex data. 

Considering our ribbon again, this was draw mode `"strip"`

![](/assets/img/meshes/draw_mode_ribbon_base.png)

And this was draw mode `"triangles"`

![](/assets/img/meshes/draw_mode_ribbon_triangles.png)

We can actually make `"triangles"` work perfectly fine by modifying the index buffer. By default, a mesh with `k` vertices will have the index buffer `{ 1, 2, 3, ..., k }`. This is why we see the behavior of `"triangles"` corrupting the ribbon, it groups them as discussed.

We can manually arrange the index buffer such that it already contains valid triangles, then override the `ribbonMesh` index buffer using `setVertexMap`:

```lua
ribbonMesh = love.graphics.newMesh(ribbonData, 
    "triangles",  -- now "triangles" instead of "strip"
    "dynamic"
)

-- manually override the index buffer
ribbonMesh:setVertexMap(
    1, 2, 3, -- triangle #1,
    2, 3, 4,
    3, 4, 5,
    4, 5, 6,
    5, 6, 7,
    6, 7, 8
)
```

Where we manually reproduce the behavior that `"strip"` would have, where each tri shares the last two vertices of the tri before

> [!CAUTION]
> **`setVertexMap` is only available if the draw mode is `"triangles"`**. If we try to `setVertexMap` on a mesh with another draw mode, an error will be raised

Drawing this mesh now:

![](/assets/img/meshes/draw_mode_ribbon_base.png)

Everything looks exactly like we want it to, by manually choosing the correct vertex map, we can draw seemingly ill-fit vertex data correctly. Note that this does not incur any significant performance overhead, as the vertex data `ribbonData` has stayed unaltered.

In summary, we should choose the draw mode to fit our mesh, but if can't make it fit, or we don't have control over the mesh, for example loading it from a file, we should make the draw mode `"triangels"` and `setVertexMap` manually. See an example of this in the [the triangulation of a polygon using math.triangulate above](#03-creating-a-polygon-mesh-using-triangulation).

## 1.5 Vertex Attribute Interpolation

We recall that we wondered in section 1.1 as to why the mesh had a smooth range of colors, instead of a single color like all the `love.graphics` shapes. We note that in our four-vertex mesh example:

```lua
local tri = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv green
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2: xy uv blue
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv red
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4: xy uv magenta
}
```

![](/assets/img/meshes/quad_hello_world.png)

The vertices have the colors of red, blue, green, and magenta respectively. 

When a mesh is drawn, the GPU automatically **interpolates** between all vertex properties, meaning it takes the property of three neighboring vertices (where neighboring means they are part of the same tri, according to the draw mode), and linearly mixes between all three vertex properties. This is done for each column in the vertex data table, including position.

For example:

```lua
local x, y, w, h = 50, 50, 200, 200
local light = function() return 0.1, 0.1, 0.1, 1 end
local dark  = function() return 0.5, 0.5, 0.5, 1  end
local vertices = {
    --    x,     y,   u, v,   rgba
    { x + 0, y + 0,   0, 0,   light() }, -- #1
    { x + w, y + 0,   1, 0,    dark() }, -- #2
    { x + w, y + h,   1, 1,    dark() }, -- #3
    { x + 0, y + h,   0, 1,   light() }, -- #4
}

local rectangle = love.graphics.newMesh(vertices, "fan", "dynamic")
```

Here, we created a rectangular mesh made up of two tris (four vertices and draw mode `"fan"`). The Vertex indices are shown in the following figure:

![](/assets/img/meshes/interpolation_gray.png)

We see that the left side of the rectangle is `dark()` and the right side is `light()`. Turning our attention to just the `1 -> 2` edge for now (the line going from vertex `1` to vertex `2`, at the top of the rectangle), we see that vertex `1` is dark, and vertex `2` is light. Therefore, the GPU will blend from the dark gray to the light gray along that edge. This is not only done for each edge, but for every pixel in the mesh.

Giving each vertex it's own color

```lua
local x, y, w, h = 50, 50, 200, 200
local green   = function() return 0, 1, 0, 1 end
local cyan    = function() return 0, 1, 1, 1 end
local magenta = function() return 1, 0, 1, 1 end
local yellow  = function() return 1, 1, 0, 1 end
local vertices = {
    --    x,     y,   u, v,   r, g, b, a
    { x + 0, y + 0,   0, 0,   green() },   -- #1
    { x + w, y + 0,   1, 0,   cyan() },    -- #2
    { x + w, y + h,   1, 1,   magenta() }, -- #3
    { x + 0, y + h,   0, 1,   yellow() },  -- #4
}
local rectangle = love.graphics.newMesh(vertices, "fan", "dynamic")
```

![](/assets/img/meshes/interpolation_color.png)

Readers are encourage to carefully trace how each color is blended between two neighboring edges as an exercise.

We also note some artifacting along the `1 -> 3` edge. This is a result of the fact that vertex properties are only blendend **inside the same tri**. For each point in the triangle, the GPU takes the distance to all three vertices, then blends each vertex property (color in this case) by taking a linear weighted average based on the distances. Because it only happens for each tri, not the entire mesh, artifacting like seen above appears.

We can fix this by manually inserting an additional vertex:

```lua
local x, y, w, h = 50, 50, 200, 200
local green   = function() return 0, 1, 0, 1 end
local cyan    = function() return 0, 1, 1, 1 end
local magenta = function() return 1, 0, 1, 1 end
local yellow  = function() return 1, 1, 0, 1 end
local center  = function() return 0.5, 0.75, 0.5, 1 end
local vertexData = {
    --    x,       y,     u,   v,   r, g, b, a
    { x + 0, y + 0,     0,   0,   green() },   -- #1
    { x + w, y + 0,     1,   0,   cyan() },    -- #2
    { x + w, y + h,     1,   1,   magenta() }, -- #3
    { x + 0, y + h,     0,   1,   yellow() },  -- #4
}

-- add new center vertex
table.insert(vertexData,
    { x + w / 2, y + h / 2, 0.5, 0.5, center() } -- #5
)

local rectangle = love.graphics.newMesh(vertexData, "triangles", "dynamic")
rectangle:setVertexMap(
    1, 2, 5, -- top triangle
    2, 3, 5, -- right triangle
    3, 4, 5, -- bottom triangle
    1, 4, 5  -- left triangle
)
```

![](/assets/img/meshes/interpolation_color_fixed.png)

Where the `setVertexMap` may be easier to follow if we label each vertex and only draw the edges:

![](/assets/img/meshes/interpolation_color_fixed_wireframe.png)

In this second version, `center` returns those values for the color because they are the component-wise average of all other four colors.

## 1.6 Texture Coordinates

While each tri interpolates between three colors, **all vertex attributes are interpolated**. This includes position, the interpolation of all three positions is the position of the specific pixel on screen, and the third default vertex attribute which we have so far negleted: **texture coordinates**.

A texture coordinate is a 2-number vector in `[0, 1]`, often called `uv`. Being in `[0, 1]` means that u is between 0 and 1 inclusive, and v is between 0 and 1 inclusive. Choose values outside this range will not result in an error.

To see how texture coordinates work and why they matter, we first need a **texture mesh**. We can associate an texture (`love.Image` or `love.Canvas`) with a mesh by using `setTexture`:

```lua
-- create the (untextured) mesh
local vertexData = {
    --    x,       y,     u,   v,   r, g, b, a
    { x + 0, y + 0,     0,   0,   green() },   -- (1)
    { x + w, y + 0,     1,   0,   cyan() },    -- (2)
    { x + w, y + h,     1,   1,   magenta() }, -- (3)
    { x + 0, y + h,     0,   1,   yellow() },  -- (4)
}
local rectangle = love.graphics.newMesh(vertexData, "fan", "dynamic")
```

Where the triangulation and draw mode are exactly the same as the 5-vertex rectangle from section at the end of section 1.5.

We see that the top left vertex (1) has a uv of `0, 0`, the top right vertex (2) has uv `1, 0`, the bottom right vertex (3) has uv `1, 1`, and the bottom left vertex (4) has uv `0, 1`.

Texture coordinates work the same as pixel coordinates, the u axis is negative going left, positive going right. And the v is **positive going down**, and negative going up. There, left vertices should have a u of `0`, fully to the left, and the right vertices should have a v of `1`, fully to the right. The top vertices should have a v of `0`, and the bottom vertices should have a v of `1`.

It may be complicated to write it out like this, but it's quite natural. It works exactly like pixel coordinates, except we are always normalized ot `[0, 1]`, instead of units in pixels.

Drawing the mesh right now, we again see:

![](/assets/img/meshes/texture_coords_untextured.png)

We now associate a texture with this mesh using `setTexture`:

```lua
local texture = love.graphics.newImage("toast.png")
rectangle:setTexture(texture)
```

Drawing again:

```lua
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(rectangle)
end
```

![](/assets/img/meshes/texture_coords_color.png)

Before we diagnose what happened here, let's first modify `vertexData`, such that each vertex is pure white `rgba = { 1, 1, 1, 1 }`:

```lua
local white = function() return 1, 1, 1, 1 end
local vertexData = {
    --    x,       y,   u,   v,   r, g, b, a
    { x + 0, y + 0,     0,   0,   white() },  -- was: green()
    { x + w, y + 0,     1,   0,   white() },  -- was: cyan()
    { x + w, y + h,     1,   1,   white() },  -- was: magenta()
    { x + 0, y + h,     0,   1,   white() },  -- was: yellow()
}
```

Drawing again:

```lua
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(rectangle)
end
```

![](/assets/img/meshes/texture_coords_uncolored.png)

Now that we have the full context, let's analyze. We first see that our texture is correctly displayed in terms of orientation. This is beceause our uv coordinates were set up as above.

We notice that with the first, non-white mesh, the color is off. This is because, by default, the interpolated vertex color is multiplied with the pixel at the position of the interpolated texture coordinates. Again, for each tri, the GPU interpolates *all* properties between each triangles vertex: color is interpolated for each pixel, and texture coordinates are interpolated for each pixel. The default shader looks up the correct pixel in the texture given the texture coordinates, then multiplies them with the color.

If we want the texture to be displayed as-is, we should choose a mesh with all-white vertices.

As an exercise, let's flip the u coordinates like so:

```lua
local vertexData = {
    --    x,       y,   u,   v,   r, g, b, a
    { x + 0, y + 0,     1,   0,   white() },  -- u was: 0
    { x + w, y + 0,     0,   0,   white() },  -- u was: 1
    { x + w, y + h,     0,   1,   white() },  -- u was: 1
    { x + 0, y + h,     1,   1,   white() },  -- u was: 0
}
```

What do we expect to see?

![](/assets/img/meshes/texture_coords_u_flipped.png)

The image is mirror along the x axis, which corresponds to our flip along the u axis.

Let's restore the uv such that the top left of the mesh gets the top left of the texture, but divide all uv by 2. What will happen?

![](/assets/img/meshes/texture_coords_uv_half.png)

We the wireframe of the mesh is displayed on top of the regular textured mesh for clarity.

Since uv is now in `[0, 0.5]`, instead of `[0, 1]`, only the top half of the texture is shown. But the rectangle is still the same size, it still interpolates just like before, resulting in a stretching of the texture. 

What happens if we go outside of `[0, 1]` for the uv?

```lua
local vertexData = {
    --    x,       y,     u,   v,   r, g, b, a
    { x + 0, y + 0,     0 * 4.5,   0 * 4.5,   white() },   -- #1
    { x + w, y + 0,     1 * 4.5,   0 * 4.5,   white() },    -- #2
    { x + w, y + h,     1 * 4.5,   1 * 4.5,   white() }, -- #3
    { x + 0, y + h,     0 * 4.5,   1 * 4.5,   white() },  -- #4
}

local rectangle = love.graphics.newMesh(vertexData, "fan", "dynamic")

local texture = rt.Texture("assets/sprites/why.png"):get_native()
texture:setWrap("repeat")
rectangle:setTexture(texture)

-- love.draw as before
```
Here, we multiplied all uv by `4.5`. We also used `setWrap` on the texture to set its wrap mode to `"repeat"`. What will this look like?

![](/assets/img/meshes/texture_coords_repeat.png)

We see a quite remarkable tiling of the image. Let's try to understand why this happens. When the GPU see a texture coordinate outside of `[0, 1]`, for example a u of `2.5`, it will map this back to `[0, 1]` by taking the module. So `2.5 % 1 = 0.5`, therefore that position is 0.5. If the GPU see a u or v outside of `[0, 1]`, it will still look into the same texture, but which pixel is chosen depends on the textures wrap mode. Remember that the rectangle is still the same size on screen, it still has the same number of pixels, but which pixel of the texture is drawn is dependend on the interpolated texture coordinate. We have chosen `repeat` here, which gives us a natural, non-integer tiling, which would be quite hard to achieve without meshes in LÖVE. 

Texture coordinates also interact with the `setFilter` property of textures. To better exhibit this, we change our rectangle mesh to fill the entire screen, and zoom in the texture coordinates by 50%:

```lua
local x, y, w, h = -- ..
local vertexData = {
    --    x,       y,     u,       v,   r, g, b, a
    { x + 0, y + 0,     0.25,   0.25,   1, 1, 1, 1 },
    { x + w, y + 0,     0.75,   0.25,   1, 1, 1, 1 },
    { x + w, y + h,     0.75,   0.75,   1, 1, 1, 1 },
    { x + 0, y + h,     0.25,   0.75,   1, 1, 1, 1 },
}
```

We then create two textures, one with `setFilter` set to `nearest`, and one with `setFilter` set to `linear`:

```lua
local left = rt.Texture("assets/sprites/why.png"):get_native()
left:setFilter("nearest")
leftRectangle:setTexture(left)

local right = rt.Texture("assets/sprites/why.png"):get_native()
right:setFilter("linear")
rightRectangle:setTexture(right)

love.draw = function()
    -- draw left: nearest-neighbor filter
    love.graphics.clear()
    love.graphics.setColor(1, 1, 1, 1)
    leftRectangle:setTexture(left)
    love.graphics.draw(rectangle)

    -- draw right: linear filter
    love.graphics.push()
    love.graphics.translate( --..
    rightRectangle:setTexture(right)
    love.graphics.draw(rectangle)
    love.graphics.pop()
end
```

![](/assets/img/meshes/texture_coords_filter.png)


We see a quite noticeable difference in how the image scales. Again, the mesh can be any kind of shape, not just a rectangle, it can be any size, the texture coordinates can be any number, and the mesh will automatically correctly scale and display any texture, regardless of texture size, an effect that could only be achieved by using many functions such as `love.graphics.scale` and `love.graphics.skew` with quite complicated math if we limit ourselves to only using `love.Quad` to display textured shapes.


## 1.7 Replacing Vertex Data

So far, we have only created a mesh and then drawn it. What if we want to change the mesh after creation? While we could create a new mesh everytime something about the vertex data changes, this is very slow and inoptimal, as it incurs significant overhead. Instead, we should **upload vertex data to an already existing mesh**. This is made possible by `setVertices`, which replaces the entire vertex data of a mesh at once. This is much faster than creating a new mesh, as a mesh is more than just the vertex data one the GPU.

## 1.7.1 Graphis Buffer Usage

With this option of replacing vertex data, we now finally turn our attention to the last argument of `newMesh`, which is a value of the enum [`BufferDataUsage`](<https://love2d.org/wiki/BufferDataUsage>).
```lua
local mesh = love.graphics.newMesh(vertexData, 
    "triangles",
    "dynamic" -- graphics buffer usage
)
```

This value decides how memory is prepared for the mesh on the GPU. It has three possible values, which roughly correspond to the following use cases.

+ `"static"`: vertex data will never be replaced
+ `"dynamic"`: vertex data may be replace sometimes
+ `"stream"`: vertex data will be replaced every frame

Setting `BufferDataUsage` does not change the meshes visuals or anything about it's vertex datas layout, it is an optimization technique that increase performance when drawing or replacing vertex data using `setVertices`. This barely matter for small meshes, but once we start uploading 100k vertices every frame, the difference between `"stream"` and `"static"` is highly relevant. `"static"` is fastest to draw and slowest to upload, `"stream"` is fastest to upload and slowest to draw, `"dynamic"` is a happy medium.

## 1.7.2 `setVertices` Example

To demonstrate the capabilities of replacing vertex data, we consider the following example:

```lua
love.window.setMode(300, 300)

local x, y, w, h = 50, 50, 200, 200
local cx, cy = x + w / 2, y + h / 2 -- center of mesh
local vertexData = {
    --    x,     y,  u,   v,    r, g, b, a
    { x + 0, y + 0,  0,   0,    1, 1, 1, 1 }, -- #1
    { x + w, y + 0,  1,   0,    1, 1, 1, 1 }, -- #2
    { x + w, y + h,  1,   1,    1, 1, 1, 1 }, -- #3
    { x + 0, y + h,  0,   1,    1, 1, 1, 1 }, -- #4
    { cx,    cy,     0.5, 0.5,  1, 1, 1, 1 }, -- #5 (center)
}

local rectangle = love.graphics.newMesh(vertexData,
    "triangles",
    "stream" -- stream, will be replaced every frame
)
rectangle:setVertexMap( -- triangulation, cf. section 1.2
    1, 2, 5,
    2, 3, 5,
    3, 4, 5,
    4, 1, 5
)
rectangle:setTexture(love.graphics.newImage("assets/sprites/toast.png"))

-- update routine: modify mesh data every frame
love.update = function(delta)
    local maxOffset = 40 -- maximum offset from center, in px
    
    -- vertex #5 (center), vertex property #1: x
    -- move cx by a random amount
    vertex[5][1] = cx + maxOffset * ((love.math.perlinNoise(love.timer.getTime()) * 2) - 1)
    
    -- vertex #5 (center), vertex property #2: y
    -- move cy by a random amount
    vertex[5][2] = cy + maxOffset * ((love.math.perlinNoise(-1 * love.timer.getTime()) * 2) - 1)

    -- upload vertices
    rectangle:setVertices(vertexData)
end

-- draw as before
love.draw = function()
    love.graphics.clear()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(rectangle)
end
```

Where `love.math.perlinNoise` (LÖVE 12.0 or newer) is used to randomly move the center vertex in a circlular area around the original center `cx, cy`. 

![](/assets/img/meshes/mesh_upload_example.png)

While the result is quit comical in this case, distorting textures using meshes like this is a powerful technique (cf. [Section 1.0.2](#102-texture-deformation)). We have free control over the position and texture coordinate of each vertex, we can change it smoothly by any amount (unlike with `love.Quad`, which only allows integers), and we can change each vertex individually. This allows for unprecendented freedom, and it why meshes are not only the most powerful drawable in LÖVE, but the basis of all drawing in modern graphics.

`setVertices` will be instrumental in the next section of this chapter, where we will use a mesh to store data for thousands of entities, and upload properties of those entities to the GPU every frame, thus changing the state of those entities

## 1.7.3 `setVertex` Example

LÖVE also provides a convenience function `setVertex`, which directly modifies a single vertex in the copy of the vertex data LÖVE holds internally:

```lua
local vertexData = { }

-- set 5th vertex, 2nd property (y-coordinate) to 250
vertexData[5][2] = 250
mesh:setVertices(vertexData) -- update mesh

-- equivalent to
mesh:setVertex(5, 2, 250) -- 5th vertex, 2nd property (y), set to 250
-- mesh updates automatically
```

Where `mesh:setVertices` is not reqiured when using `setVertex`. With `setVertex`, we don't have to manually keep a CPU-side copy of the vertex data, making it convenient if only a few vertices (instead of a majority of them) change every frame.

---

---

## 2. Data Meshes & Mesh Attribute Attachment

## 2.0 Why Use Custom Meshes?

While meshse are already complicated, rest of this chapter will be even more technical. Both beginner and intermediate users of LÖVE may feel overwhelmed, because LÖVE in general is designed to fully abstract all the manual labor graphics programming requires under the hood. To help with motivation, we should first consider why we would ever want to use a custom mesh?

Internally, a mesh is a **graphics buffer**. A graphics buffer is a section of memory that is on the card. Note that it can be almost any kind of memory, as long as it is numbers. With flexible thinking about how to encode certain things as number, **we can send any kind of data to the CPU**. This opens up some very powerful techniques. For examples, let's say we want to make a ["Vampire Survivors"](https://store.steampowered.com/app/1794680/Vampire_Survivors/)-type game, which is notorious for having thousands of sprites on screen at once:

![](/assets/img/meshes/vampire_survivors.png)

*(Source: [Rock Paper Shotgun](<https://www.rockpapershotgun.com/vampire-survivors-early-access-review>), Copyright: [poncle](<https://store.steampowered.com/search/?developer=poncle>))*

Let's say instead of these enemies being images, which a `love.SpriteBatch` could handle, we want them to be arbitary shapes, not just images. Maybe we want to create a shmup with the entire screen fille with animated bullets, or we want to thousands of snowflakes falling gently as a weather effect. How can the GPU handle that many entities? A naive approach would almost certainly tank the framerate, especially when the effect is drawn on top of the rest of an entire game. To achieve effects like this, meshes are required. By using a GPU feature called **geometry instancing along with custom meshes**, we can store all the data for the enemies or bullets or snowflakes on the GPU, and have it render all of them in a single instruction. This is the power of custom meshes, and is how things like `love.SpriteBatch` or `love.ParticleSystem` are implemented internally.

With a hopefully increased amount of motivation, we turn our attention on how to actually achieve this.

## 2.1 Vertex Attribute Format

`newMesh` has an overload which we have so far not used here:

```lua
--- @param
love.graphics.newMesh = function(
    vertexFormat,   -- Table<Table>
    verexData,      -- Table<Table>
    drawMode,       -- love.MeshDrawMode 
    bufferUsage     -- love.SpriteBatchUsage
)
```
Where `drawMode` is one of the familiar `"triangles"`, `"fan"`, `"strip"`, `bufferUsage` is one of `"static"`, `"dynamic"`, `"stream"`. We have discussed these in sections [1.2](#12-mesh-draw-modes) and [1.7.1](#171-graphis-buffer-usage) respectively.

For `vertexFormat`, we so far assumed it to be a table of the following format:

```lua
local data = {
    { x, y, u, v, r, g, b, a }, -- Vertex #1
    { x, y, u, v, r, g, b, a }, -- Vertex #2
   -- more vertices
}
```

Where `xy` is the vertex's position, `uv` is the vertex'S texture coordinate, and `rgba` is the vertex's color. This is the **default vertex format** uses, however we can use a **custom vertex format** using `newMesh` first argument. The vertex format is a table of the following form, where k is the number of vertex attributes:

```lua
local vertexFormat = {
    { 
        location = -- Index in [0, ..., k - 1]
        name = -- String
        format = -- love.DataFormat
    }
}
```

It's probably best to look at an example. We want to reproduce LÖVE's default vertex format, xy position, uv texture coordinate, rgba color, in that order. It would look as follow:

> [!CAUTION]
> Between LÖVE version 11.5 and 12.0, vertex attribute declaration format was changed completely. The following will only work in LÖVE 12.0 or newer!

```lua
local defaultFormat = {
    {
        location = 0, -- attribute #1 (0-based)
        name = "VertexPosition", -- cleartext name
        format = "floatvec2" -- format
    },

    {
        location = 1, -- attribute #2 (0-based)
        name = "VertexTexCoords",
        format = "floatvec2",
    },

    { 
        location = 2, -- attribute #3
        name = "VertexColor",
        format = "floatvec4"
    }
}
```

We see that `location` is 0-based, as opposed to the rest of lua which is usually 1-based. This is because `location` will be handed to the shader, which is written in glsl which uses 0-based indexing. The `name` for each format can be freely chosen by the developer, while `format` is a value of the LÖVE enum `DataFormat`, which we will look at soon. First we should again look at how the vertex attribute format corresponds to the actual vertex data. 

```lua
local vertexData = {
    { -- Vertex #1
        200, 300,   -- Attribute #1: "VertexPosition" (2 components)
        0.3, 0.8,   -- Attribute #2: "VertexTexCoords" (2 components)
        1, 0, 1, 1  -- Attribute #3: "VertexColor" (4 components)
    },

    { 300, 150, 0.2, 0.9, 1, 1, 0, 1 }, -- Vertex #2
    { 100, 230, 0.0, 1.0, 0.3, 0.5, 1, 1 }, -- Vertex #2
    -- ...
}
```
We see that, because `VertexPosition` is a `floatvec2`, which has 2 components, the first part of each vertices data has to be 2 numbers. `VertexTexCoords` is another `floatvec2` and has 2 components, so another 2 numbers, while `VertexColor` is a `floatvec4` which has 4 components, therefore expecting 4 more numbers. Because all the vertex data for a single vertex is stored as a flat table, each vertex should therefore has `2 + 2 + 4 = 8` numbers. It's important to realize how each vertex attributes corresponds to which indices for each vertex, as malformatting or omitting any numbers in the vertex data may corrupt the mesh. This is also true when using numbers like `math.huge` (infinite) or `NaN`.

### 2.1.1 Vertex Attribute Format

How do we know how many numbers each attribute expectes? The `format` field of a vertex attribute specification is a value of enum `love.DataFormat`, which can have one the following values, where the corresponding GLSL type and number components is given:

Here's the table with a value range column added:

| Name | GLSL Type | # components | value range                    |
|---|---|---|-----------------------------|
| `"float"` | `float` | `1` | 32-bit float                |
| `"floatvec2"` | `vec2` | `2` | 32-bit float                |
| `"floatvec3"` | `vec3` | `3` | 32-bit float                |
| `"floatvec4"` | `vec4` | `4` | 32-bit float                |
| `"int32"` | `int` | `1` | `[-2147483648 - 2147483647]` |
| `"int32vec2"` | `ivec2` | `2` | `[-2147483648 - 2147483647]` |
| `"int32vec3"` | `ivec3` | `3` | `[-2147483648 - 2147483647]` |
| `"int32vec4"` | `ivec4` | `4` | `[-2147483648 - 2147483647]` |
| `"uint32"` | `uint` | `1` | `[0 - 4294967295]`          |
| `"uint32vec2"` | `uvec2` | `2` | `[0 - 4294967295]`          |
| `"uint32vec3"` | `uvec3` | `3` | `[0 - 4294967295]`          |
| `"uint32vec4"` | `uvec4` | `4` | `[0 - 4294967295]`          |
| `"snorm8vec4"` | `vec4` | `4` | `[-1.0 - 1.0]`              |
| `"unorm8vec4"` | `vec4` | `4` | `[0.0 - 1.0]`               |
| `"int8vec4"` | `ivec4` | `4` | `[-128 - 127]`              |
| `"uint8vec4"` | `uvec4` | `4` | `[0 - 255]`                 |
| `"snorm16vec2"` | `vec2` | `2` | `[-1.0 - 1.0]`              |
| `"snorm16vec4"` | `vec4` | `4` | `[-1.0 - 1.0]`              |
| `"unorm16vec2"` | `vec2` | `2` | `[0.0 - 1.0]`               |
| `"unorm16vec4"` | `vec4` | `4` | `[0.0 - 1.0]`               |
| `"int16vec2"` | `ivec2` | `2` | `[-32768 - 32767]`          |
| `"int16vec4"` | `ivec4` | `4` | `[-32768 - 32767]`          |
| `"uint16"` | `uint` | `1` | `[0 - 65535]`               |
| `"uint16vec2"` | `uvec2` | `2` | `[0 - 65535]`               |
| `"uint16vec4"` | `uvec4` | `4` | `[0 - 65535]`               |

Note that since **all numbers in Lua are floats**, they get truncated to the nearest glsl type when the vertex data is send to the GPU. For example, `-3.4` for a `uint16` vertex attribute will automatically discard the `.4` and then wrap to the correct 16-bit unsigned integer without an error message, resulting in `65536 - 3 = 65533`. This is true for the multi-component integer vectors too, so we need to be careful when contsructing the vertex data.

As an example, let's create a seemingly exotic mesh. Conceptually, we want the first vertex attribute to be a 2-component vector of floats, the second component to be a single float, and the third component to be a boolean, which we will encoded as a 32-bit unsigned integer:

```lua
local vertexFormat = {
    {
        location = 0, -- attribute #1
        name = "VertexOffset",
        format = "floatvec2" -- 2-component float vector
    },

    {
        location = 1, -- attribute #2
        name = "VertexScale",
        format = "float", -- 1-component float
    },

    {
        location = 2, -- attribute #3,
        name = "VertexShouldDraw",
        format = "uint32" -- 1-component 32-bit unsigned int
    }
}
```

We can now create the vertex data and mesh:

```lua
local bool2uint32 = function(x) if x then return 0x1 else return 0x0 end
local vertexData = {
    { -- vertex #1
        300, 200, -- attribute #1 `floatvec2` (2 components)
        2,        -- attribute #2 `float` (1 component)
        bool2uint32(true) -- attribute #3 `uint32` (1 component)
    },

    { -- vertex #2,
        -200, 120, -- attribute #1 `floatvec2`
        4,         -- attribute #2 `float`
        bool2uint32(false) -- attribute #3: `uint32`
    },
    
    -- ...
}

local exoticMesh = love.graphics.newMesh(
    vertexFormat, -- table of vertex attribute formats
    vertexData,   -- mesh vertex data
    "triangles",   -- draw mode (unused)
    "dynamic"     -- graphics buffer usage
)
```

LÖVE will initialize this mesh perfectly fine, `setVertices` works, and the mesh technically has a draw mode. If we actually try to draw this mesh however, LÖVE will not error, instead drawing a corrupted nonsense to the screen. This is because **we are using the wrong shader**. LÖVE not only has a default mesh format, but a **default shader** it will use when drawing a `love.Mesh` with no shader bound ( `love.graphics.getShader(nil)`). This shader is hardcoded to expect the default vertex format. For example, the default shader expects rgba, a `vec4` at attribute position #3 (`location = 2`), meaning it expects four floats for position #3, while we just gave it a single `uint32`. **To properly use and render custom vertex format meshes, we need a custom shader**.

## 2.2 Custom Vertex Attribute Shader



```lua

-- [[
local function generateSpiralTris(n, turns)
    n = n or 6
    turns = turns or 2.5 -- how many full revolutions the spiral makes

    -- 1) Build the spiral centerline points (n+1 of them), plus the shell's
    --    center point. Radius grows with t so the spiral opens outward,
    --    like a nautilus.
    local center = { x = 0, y = 0 }
    local spiralPts = {}
    for i = 0, n do
        local t = i / n
        local angle = t * turns * math.pi * ((n-1) / n) -- full rotations, correctly scaled
        local radius = t ^ 0.4
        spiralPts[#spiralPts + 1] = {
            x = radius * math.cos(angle),
            y = radius * math.sin(angle),
            t = t,
        }
    end

    -- 2) Triangulate as a fan: (center, spiralPts[i], spiralPts[i+1])
    local verts = {}
    for i = 1, n do
        local p0 = center
        local p1 = spiralPts[i]
        local p2 = spiralPts[i + 1]

        -- color: sweep hue along the spiral for a nice shell-banding look
        local hue = (i - 1) / n
        local r0, g0, b0 = rt.hsva_to_rgba(hue, 1.0, 1.0, 1)          -- near-white center
        local r1, g1, b1 = rt.hsva_to_rgba(hue, 1.0, 1.0, 1)
        local r2, g2, b2 = rt.hsva_to_rgba(hue, 1.0, 1.0, 1)

        -- uv: radius -> v, angle fraction -> u
        local u0, v0 = 0.5, 0.5
        local u1, v1 = 0.5 + p1.x * 0.5, 0.5 + p1.y * 0.5
        local u2, v2 = 0.5 + p2.x * 0.5, 0.5 + p2.y * 0.5

        verts[#verts + 1] = { p0.x, p0.y, u0, v0, r0, g0, b0, 1.0 }
        verts[#verts + 1] = { p1.x, p1.y, u1, v1, r1, g1, b1, 1.0 }
        verts[#verts + 1] = { p2.x, p2.y, u2, v2, r2, g2, b2, 1.0 }
    end

    -- 3) Fit + center into a rectangle of size (love.graphics.getWidth(), love.graphics.getHeight())
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, v in ipairs(verts) do
        minX = math.min(minX, v[1])
        maxX = math.max(maxX, v[1])
        minY = math.min(minY, v[2])
        maxY = math.max(maxY, v[2])
    end

    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    local spanX, spanY = (maxX - minX), (maxY - minY)
    -- avoid div-by-zero for degenerate n
    spanX = spanX > 0 and spanX or 1
    spanY = spanY > 0 and spanY or 1

    -- uniform scale so the whole spiral fits inside W x H, with a small margin
    local margin = 0.9
    local scale = math.min(W / spanX, H / spanY) * margin

    local cx, cy = (minX + maxX) * 0.5, (minY + maxY) * 0.5
    local ox, oy = W * 0.5, H * 0.5

    for _, v in ipairs(verts) do
        v[1] = (v[1] - cx) * scale + ox
        v[2] = (v[2] - cy) * scale + oy
    end

    return verts
end

local data = generateSpiralTris(18)
local mesh = love.graphics.newMesh(data, "fan")
--
```