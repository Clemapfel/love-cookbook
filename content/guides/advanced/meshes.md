---
title: "Meshes"
authors: [clemapfel]
date: 2026-07-14
---

# Meshes

This chapter will cover **Meshes**, which are a central concept in graphics programming and are used to display any geometry on screen. While rarely used by beginners thanks to LÖVEs high level of abstraction, meshes are actually used internally by LÖVE for displaying any kind of graphics, including for `love.graphics.rectangle`, `love.graphics.circle`, `love.graphics.polygon`, and `draw`ing `Images`, `SpriteBatche`s, `ParticleSystem`s, etc.

By mastering meshes, we can extend LÖVEs graphical capability significantly, rendering shapes not possible with LÖVEs existing high-level API, and achieving performance even better what basic usage of LÖVE can offer.

---

## Table of Contents

---

# 0. TL;DR: Quick Start

Given here are code snippets that illustrate basic usage of meshes. These are **intended to be referenced after having read this chapter**. Readers new to meshes are not expected to understand these snippets, and should [skip to section 1 of this chapter](#10-what-are-meshes-motivation).

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

Scrolling past the code snippets in section 0, meshes can seem quit intimidating both from a conceptual and implementation site. Before diving into this topic, we may want to first answer the question of why and when we would want to use meshes at all? What are situations where we *have* to use meshes, situations where no other LÖVE API can achieve a certain result.

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

While 3D in this example, a technique that could be used to render tens of thousands of blades of grass in games like "Breath of the Wild" is a graphical capability of most modern GPUs called *geometry instancing*. This technology is available in LÖVE, and LÖVE could match Nintendos custom engine capabilities at least in this specific instance of drawing the same shape, slightly altered, tens of thousands of times. Achieving this in 2D compared to 3D is trivial.

![](/assets/img/meshes/botw_grass.png)

*(Source: [Nintendo Eshop](<https://www.nintendo.com/us/store/products/the-legend-of-zelda-breath-of-the-wild-switch/>), Copyright: Nintendo)*

## 1.1 Glossary: Vertices, Edges, Tris, Meshes

With us now hopefully motivated to put in the effort to understand meshes in order to unlock unlimited and highly advanced graphical capabilities in LÖVE, we will turn our attention to terminology. While this chapter will avoid math such as differential geometry as much as possible, certain terms are unavoidable when speaking about meshes in a technical sense.

A **vertex** (plural: *vertices*) is a point in space (2D or 3D). It has an x coordinate and y coordinate, as well as certain other properties, such as a color (encoded as four numbers, red, green, blue, opacity).

Given *exactly two vertices*, an **edge** is a straight line drawn from the first vertices position to the second. An edge is unordered, meaning the edge from vertex A to B is the same object as an edge from B to A. 

Given *exactly three vertices*, a **tri** is the triangle that is defined by these 3 points. This is sometimes called a *face* in math, but *tri* is more common when talking about it in relation to graphics programming and gamedev.

A **mesh**, then, is a collection of one or more tris. Note that these tris do not need to be connected, though they can be. Since vertices can be 2D or 3D, tris, too, can be 2D or 3D, but any property other than the number of coordinates for the position transfers and there is no difference between 2D and 3D for our purposes. 

In LÖVE, unless otherwise specified, vertices have the following properties, where we will explain what uv coordinates are in the next section.

+ **position**: two numbers for the x-coordinate and y-coordinate, in pixels
+ **texture coordinates**: two numbers for the u-coordinates and v- coordinate, each normalized to the value range `[0, 1]`
+ **color**: four numbers, one for the r, g, b, and a (alpha / opacity), each normalized to the value range `[0, 1]`

These properties are stored inline, meaning a vertex with this **vertex format** (position, texture coordinate, color) is described as follows.

```lua
local vertex = { 
    200, 300, -- x, y
    0.3, 0.4, -- u, v
    1, 0, 1, 0.5 -- r, g, b, a
}
```

A tri then, is a table of three vertices:

```lua
local tri = {
    { -- vertex #1
        45, 170, -- xy
        0.0, 0.0, -- uv
        1.0, 0.0, 0.0, 1.0 -- rgba 
    },
    { -- vertex #2
        210, 45, 
        1.0, 0.0, 
        0.0, 1.0, 0.0, 1.0 
    },
    { -- vertex #3
        200, 235, 
        0.5, 1.0, 
        0.0, 0.0, 1.0, 1.0 
    },
}
```

A table that contains three or more vertices, defining one or more tris, will can also be called **vertex data**. 

Now that we have a tri, we can finally draw our first mesh. Recall that a mesh is a collection of tris, so one tri is a mesh.

We use `love.graphics.newMesh` to create a mesh, and `love.graphics.draw` to draw it. It reacts to `setColor` as does any other `love.graphics` shape. We will not touch on the last two parameters for this function for now, they will be explained in a later section

```lua
local tri = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv rgba
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2: xy uv rgba
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv rgba
}

local mesh = love.graphics.newMesh(tri, "fan", "dynamic")

love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
end
```

![](/assets/img/meshes/tri_hello_world.png)

Before we analyze this image, let's add another vertex first:

```lua
local tri = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv green
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2: xy uv blue
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv red
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4: xy uv magenta (NEW)
}

local mesh = love.graphics.newMesh(tri, "fan", "dynamic")

love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
end
```

![](/assets/img/meshes/quad_hello_world.png)

Two question arise: 
+ (i) Why do *four* vertices result in a valid mesh, when meshes are collection of triangles?
+ (ii) Why is mesh colored like that, with a smooth mix between colors?

Turning our attention to (i) first, we can use one of LÖVEs rarely used API to answer this question. `love.graphics.setWireframe` makes any mesh draw call after display the *edges* instead of the triangles themself. 

```lua
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setWireframe(true)
    love.graphics.draw(mesh)
    love.graphics.setWireframe(false)
end
```

![](/assets/img/meshes/quad_hello_world_wireframe.png)

This confirms that the mesh is actually made up out of two valid triangles, so our definition of a mesh being a collection of triangles is correct. We notice that the two triangles share an edge. This is a key observation. Indeed, we can reproduce the above shape like so:

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
    
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1: xy uv green
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3: xy uv red
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4: xy uv magenta
}

local mesh = love.graphics.newMesh(tri, 
    "triangles", -- NEW: was "fan"
    "dynamic"
)

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

The second argument of `love.graphics.newMesh` is called the **draw mode**, which is a value of the enum [`love.MeshDrawMode`](https://love2d.org/wiki/MeshDrawMode). The draw mode determines how the list of vertices in the vertex data is treated when constructing the list of tris internally. It's best to visualize this process, we generate the following shape:

TODO

## 1.2.1 `setVertexMap`

If the draw mode is `triangles` specifically, a new API opens up: `setVertexMap`. This function takes a list of 1-based vertex indices, which will be the order the GPU considers the vertices when constructing the list of triangles. For example, the following two meshes are identical:

```lua
local tri = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 }, -- #1
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4
}

local fan = love.graphics.newMesh(tri, 
    "fan",  -- mode "fan", 2 -> 3 edge is duplicated
    "dynamic"
)

local triangles = love.graphics.newMesh(tri,
    "triangles", -- mode "triangles", `setVertexMap` used for triangulation
    "dynamic"
)

triangles:setVertexMap(
    1, 2, 3, -- top left triangle
    1, 3, 4  -- bottom right triangle
)
```

`setVertexMap` is preferred over manually duplicating vertices in the vertex data like this:

```lua
local fourVertices = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 }, -- #1
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4
}

local fourMesh = love.graphics.newMesh(fourVertices, "triangles", "dynamic")

-- manually triangulate
fourMesh:setVertexMap(
    1, 2, 3,
    1, 3, 4
)

-- visually the same as 

local six = {
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1
    { 210, 45, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0 },  -- #2
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3
    
    { 45, 170, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },  -- #1
    { 200, 235, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0 }, -- #3
    { 120, 280, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0 }, -- #4
}


local sixMesh = love.graphics.newMesh(six, "triangles", "dynamic")
-- no setVertexMap
```

While these two meshes look the same when drawn, GPU-side the `six` vertex data takes up 33% more memory than the `four` data. While this is insignificant for a mesh with so few vertices and triangles, in gamedev practice meshes can sometimes contains tens of thousands of vertices. In that case, a 33% memory overhead may become significant.  

## 1.3 Vertex Attribute Interpolation

We recall that we wondered in section 1.2 as to why the mesh had a smooth range of colors, instead of a single color. We note that in our four-vertex mesh example:

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

When a mesh is drawn, the GPU automatically **interpolates** between all vertex properties, meaning it takes the property of two neighboring vertices (where neighboring means they are part of an edge, according to the draw mode), and linearly moves from one value to the other.

For example:

```lua
local x, y, w, h = 50, 50, 200, 200
local light = function() return 0.1, 0.1, 0.1, 1 end
local dark = function() return 0.5, 0.5, 0.5, 1  end
local vertices = {
    --    x,     y,   u, v,   r, g, b, a
    { x + 0, y + 0,   0, 0,   light() }, -- #1
    { x + w, y + 0,   1, 0,    dark() }, -- #2
    { x + w, y + h,   1, 1,    dark() }, -- #3
    { x + 0, y + h,   0, 1,   light() }, -- #4
}

local rectangle = love.graphics.newMesh(vertices, "fan", "dynamic")
```

Here, we create a rectangular mesh made up of two tris. The Vertex indices are shown in the following figure:

![](/assets/img/meshes/interpolation_gray.png)

We see that the left side of the rectangle is `dark()` and the right side is `light()`. Turning our attention to just the `1 -> 2` edge for now (the line going from vertex `1` to vertex `2`, at the top of the rectangle), we see that vertex `1` is dark, and vertex `2` is light. Therefore, the GPU will blend from the dark gray to the light gray along that edge. This is not only done for each edge, but for every pixel in the mesh.

Giving each rectangle it's own color

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

We also note some artifacting along the `1 -> 3` edge. This is a result of the fact that vertex properties are only blendend **inside the same tri**. For each point in the triangle, the GPU takes the distance to all three vertices, then blends each vertex property (color in this case) by taking a weighted average based on the distances. Because it only happens for each tri, not the entire mesh, artifacting like seen above appears.

We can fix this by manually inserting an additional vertex:

```lua
local x, y, w, h = 50, 50, 200, 200
local green   = function() return 0, 1, 0, 1 end
local cyan    = function() return 0, 1, 1, 1 end
local magenta = function() return 1, 0, 1, 1 end
local yellow  = function() return 1, 1, 0, 1 end
local center  = function() return 0.5, 0.75, 0.5, 1 end
local vertices = {
    --    x,       y,     u,   v,   r, g, b, a
    { x + 0, y + 0,     0,   0,   green() },   -- #1
    { x + w, y + 0,     1,   0,   cyan() },    -- #2
    { x + w, y + h,     1,   1,   magenta() }, -- #3
    { x + 0, y + h,     0,   1,   yellow() },  -- #4
}

-- add new center vertex
table.insert(vertices,
    { x + w / 2, y + h / 2, 0.5, 0.5, center() } -- #5
)

local rectangle = love.graphics.newMesh(vertices, "triangles", "dynamic")
rectangle:setVertexMap(
    1, 2, 5, -- top triangle
    2, 3, 5, -- right triangle
    3, 4, 5, -- bottom triangle
    4, 1, 5  -- left triangle
)
```

![](/assets/img/meshes/interpolation_color_fixed.png)

Where the `setVertexMap` may be easier to follow if we label the center and only draw the edges

![](/assets/img/meshes/interpolation_color_fixed_wireframe.png)

In this second version, `center` returns those values for the color because they are the component-wise average of all other four colors.

## 1.3 Texture Coordinates

## 1.4 Replacing Vertex Data

So far, we have only created a mesh and then drawn it. What if we want to change the mesh after creation? While we could create a new mesh everytime something about the vertex data changes, this is very slow and inoptimal, as it incurs significant overhead. Instead, we should **upload vertex data to an already existing mesh**. This is made possible by `setVertices`, which replaces all vertices of a mesh at once.

## 1.5 Graphis Buffer Usage

We now finally turn our attention to the last argument of `newMesh`, which is a value of the enum [`BufferDataUsage`](<https://love2d.org/wiki/BufferDataUsage>).
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

## 1.5.1 `setVertices` Example

To demonstrate the capabilities of replacing vertex data, we consider the following example:

```lua
love.window.setMode(300, 300)

local x, y, w, h = 50, 50, 200, 200
local cx, cy = x + w / 2, y + h / 2 -- center of mesh
local vertices = {
    --    x,     y,  u,   v,   r, g, b, a
    { x + 0, y + 0,  0,   0,    1, 1, 1, 1 }, -- #1
    { x + w, y + 0,  1,   0,    1, 1, 1, 1 }, -- #2
    { x + w, y + h,  1,   1,    1, 1, 1, 1 }, -- #3
    { x + 0, y + h,  0,   1,    1, 1, 1, 1 }, -- #4
    { cx,    cy,     0.5, 0.5,  1, 1, 1, 1 }, -- #5 (center)
}

local rectangle = love.graphics.newMesh(vertices,
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
    local vertex = vertices[5] -- center vertex
    local maxOffset = 40 -- maximum offset from center, in px
    
    -- vertex property #1: x
    -- move cx by a random amount
    vertex[1] = cx + maxOffset * ((love.math.perlinNoise(love.timer.getTime()) * 2) - 1)
    
    -- vertex property #2: y
    -- move cy by a random amount
    vertex[2] = cy + maxOffset * ((love.math.perlinNoise(-1 * love.timer.getTime()) * 2) - 1)

    -- upload vertices
    rectangle:setVertices(vertices)
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

While the result is quit comical in this case, distorting textures using meshes like this is a powerful technique (cf. [Section 1.0.2](#102-texture-deformation)). Furthermore, `setVertices` will be instrumental in the next section of this chapter, where we will use a mesh to store data for thousands of entities, and upload properties of those entities to the GPU every frame, thus changing the state of those entities. This allows us draw all of those entites with a single draw call (as forecast in [Section 1.0.3](#103-rendering-tens-of-thousands-of-the-same-shape)).

## 1.5.2 `setVertex` Example

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

## 2.0 Data Meshes & Mesh Attribute Attachment

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