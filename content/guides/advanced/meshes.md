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

# 2. Advanced Usage

> [!CAUTION]
> Unlike before, the rest of this chapter is intended for users already familiar with advanced concepts in graphics programming, including glsl shaders, geometry instancing, vertex attributes, vertex buffers, index buffers, storage buffers, texel buffers, and C-memory. It will be assumed that readers are somewhat familiar with these concepts for the rest of this chapter.

The following fully functional code example shows various advanced techniques, which are listed here. We can navigate to the relevant code section using the section identifiers, e.g. for section `X.4`, a code comment `-- (X.4) ...` will be present in the admittedly large code example below, which users are encouraged to `ctrl+f` for.

#### 2.1 Geometry Instancing

Geometry instancing is a technique that allows use to draw `n` copies of a mesh using a single draw command. For this to be useful, we need each copy to have some kind of data associated with that allows use to modify a property of it, otherwise instanced drawing will just draw the same mesh at the same position `n` times.

To perform an instanced draw, we use `love.graphics.drawInstanced(mesh, n)` in the code example below). Before this commend, we should bind a custom vertex shader which uses some kind of GPU-side data type to store the per-instance attributes. In the code example below, a circle mesh is used for drawing. Each instance gets it's own position (`InstanceOffset`), scale (`InstanceScale`) and hue (`InstanceHue`). To properly scale and offset the mesh, it is constructed at origin, meaning the center vertex is at `(0, 0)`, and it's radius is normalized to `1`. This way, we can simply offset the circle by `InstanceOffset`, then scale it by `InstanceScale`. Because the circle was normalized before, this makes it so the circle is now at the correct position and has the correct radius on screen.

To access the per-instance attributes, the below code examples shows how to use vertex buffers, storage buffers, and texel buffers to store this data on the GPU, then query them in the vertex shader. Each of these types of buffers is represented by a Lua-side object, either a `love.Mesh` for vertex buffers, or a `love.GraphicsBuffer` for storage and texel buffers. Each type of buffer can be filled with data from either a regular Lua table or C-data in the form of `love.ByteData`. Since modifying `ByteData` using it's method, such as `setFloat` and `setUInt32`, is quite slow, the below example also shows how to modify the C-data directly using LuaJITs FFI library. In terms of performance, this is optimal, if uploading or modifying the CPU-side data is a bottleneck, we should choose either a vertex or storage buffer and keep the data as C-memory. This saves a lot of internal conversion and can lead to a multiple-fold speedup for large buffers.

Using instanced drawing, with a graphics buffer to store per-instance attributes which is updated from C-data using `ffi` is the recommended way to match or exceed performance of LÖVE native functions such as `love.graphics.circle` or `SpriteBatch`, and is the most performant way to draw or send data to the GPU in LÖVE. This technique is used in the example below to draw hundreds of thousands of meshes at 60fps.

Section relevant to geometry instancing in general include:

+ `(A.1)` specifying a custom vertex attribute format for the drawn mesh
+ `(A.2)` creating the drawable mesh
+ `(A.3)` performing the  `drawInstanced` command
+ `(A.4)` binding a shader before instanced drawing
+ `(A.5)` applying the per-instance mesh transform in the vertex shader
+ `(A.6)` declaring the per-instance data buffer format
+ `(A.7)` initializing the per-instance data
Sections relevant to specific types of buffers are listed in the following sections.
+ `(A.8)` creating the custom shader for use with  `drawInstanced`

#### 2.2 Vertex Buffers

Vertex buffers are represented by a `love.Mesh` CPU-side, which takes as it's first argument the buffer format (cf. section (`A.0`) below. 
In LÖVE 12.0, we can use `getVertexBuffer` to access the raw `love.GraphicsBuffer` of the underlying mesh, but to create a vertex buffer we still need use `newMesh`. Similarly, to access the index buffer we can use `getIndexBuffer`, while setting the index buffer is accomplished using  `setVertexMap` as detailed in section 1.3.

The code example includes the following sections relevant to vertex buffers

+ `(B.1)` declaring a custom vertex buffer format
+ `(B.2)` initializing a vertex buffer from a Lua table
+ `(B.3)` initializing a vertex buffer from `love.ByteData`
+ `(B.4)` creating the vertex buffer object
+ `(B.5)` initializing a vertex buffer from FFI memory
+ `(B.6)` attaching attributes from one mesh to another, per-vertex or per-instance
+ `(B.7)` accessing attributes of vertex buffer in the vertex shader

#### 2.3 **Storage Buffers**

Storage buffers are initialized CPU-side using `newBuffer`, which, just like `newMesh` (when using it for vertex buffers) takes a buffer format as it's first argument and a lua table with the initial data as the second. The object returned, a `love.GraphicsBuffer` is both used to upload data to a storage buffer (a glsl `buffer`, cf. section `TODO` below), and to texel buffers (cf. section `TODO`).

Relevant sections of the code example to storage buffers include

+ `(C.1)` declaring a custom storage buffer format
+ `(C.2)` initializing the storage buffer from a Lua table
+ `(C.3)` initializing the storage buffer from `love.ByteData`
+ `(C.4)` initializing the storage buffer from FFI memory
+ `(C.5)` declaring a matching buffer format in glsl
+ `(C.6)` declaring the storage buffer uniform
+ `(C.7)` using `gl_IntanceID` to access per-instance attributes of the storage buffer in the vertex shader
+ `(C.8)` binding a storage buffer to a glsl `buffer` declaration

#### 2.4 **Texel Buffers**

Texel buffers, called `samplerBuffer` in a glsl shader, can hold up to 4 float attributes (or ints for `isamplerBuffer`, uints for `usamplerBuffer`), and are represented CPU-side by a `love.GraphicsBuffer`. When creating the buffer format for a texel buffer, we need to make sure that it has exactly 1 entry, which contains 1 or more components of the same type. For example

```lua
local texelBufferFormat = {
    -- WRONG
    { location = 0, name = "First", format = "float" },
    { location = 1, name = "First", format = "float" },
    { location = 2, name = "First", format = "float" },
    { location = 3, name = "First", format = "float" }
}
```
Is incorrect, it should be

```lua
local texelBufferFormat = {
    -- CORRECT
    { location = 0, name = "All", format = "floatvec3" }
}
```

See section `TODO` below.

Texel buffer usage in the code example below includes:

+ `(D.1)` declaring a custom texel buffer format
+ `(D.2)` initializing the texel buffer from a Lua table
+ `(D.3)` initializing the texel buffer from `love.ByteData`
+ `(D.4)` initializing the texel buffer from FFI memory
+ `(D.5)` binding the texel buffer to a shader uniform
+ `(D.6)` declaring the texel buffer uniform
+ `(D.7)` using `gl_InstanceID` to index access per-instance attributes of the texel buffer in the vertex shader.

### 2.5 Mesh Advanced Usage Example

> [!NOTE]
> Modify `BUFFER_MODE` to change which buffer type (vertex, storage, texel) is use;  modify `DATA_MODE` to change which kind of CPU-side data `(table, ByteData, FFI memory)` is used to fill the buffer.


> [!TIP]
> This code example is quite long and complicated due to the nature of the advanced techniques used. To compensate, it has a lot of comments and works out-of-the-box. Try copy-pasting it into a main.lua and running it using LÖVE 12, it will draw 100000 circles at 60 fps! As an exercise, consider adding or changing one of the per-instance attributes, maybe replace `InstanceHue` with `InstanceColor`.

```lua
ffi = require "ffi"

-- ### CONFIG ###

-- usage mode, decides which LÖVE 12.0 method to use for representing the instance date
local BUFFER_MODE_USE_VERTEX_BUFFER = "vertexbuffer"
local BUFFER_MODE_USE_TEXEL_BUFFER = "texelbuffer"
local BUFFER_MODE_USE_STORAGE_BUFFER = "storagebuffer"
local BUFFER_MODE = BUFFER_MODE_USE_STORAGE_BUFFER

-- upload mode, decides whether to use lua tables, `ByteData` or ffi data to upload the instance data
local DATA_MODE_USE_TABLES = "table"
local DATA_MODE_USE_BYTE_DATA = "bytedata"
local DATA_MODE_USE_FFI_DATA = "ffi"
local DATA_MODE = DATA_MODE_USE_FFI_DATA

-- ### GLOBALS ###

local drawMeshFormat -- table, vertex attribute format of mesh that will be drawn
local drawMesh -- love.Mesh, actual mesh that will be the shape of the particles
local drawShader -- love.Shader, custom shader that retrieves the per-instance data

local instanceCount = 100000 -- number of draw instances
local perInstanceFormat -- table, vertex attribute format of data mesh
local perInstanceData -- table of `love.ByteData`, CPU-side copy of per-instance data
local perInstanceDataBuffer -- `love.GraphicsBuffer`, GPU-side copy of per-instance data

--- ### INITIALIZATION ###

local generateOffset, generateScale, generateHue -- see "internals" below
local modifyOffset, modifyScale, modifyHue

love.load = function()
    -- (A.1) declare vertex attribute format of draw mesh
    drawMeshFormat = {
        { -- instance mesh attribute #1: position
            location = 0,            -- attribute #1 (0-based)
            name = "VertexPosition", -- name
            format = "floatvec2"     -- glsl format: vec2 (2 components)
        },

        { -- instance mesh attribute #2: texture coordinates
            location = 1,            -- attribute #2 (0-based)
            name = "VertexTextureCoordinates",
            format = "floatvec2"     -- glsl format: vec2 (2 components)
        },

        { -- instance mesh attribute #2: texture coordinates
            location = 2,            -- attribute #3 (0-based)
            name = "VertexColor",
            format = "floatvec4"     -- glsl format: vec4 (2 components)
        }
    }

    -- (A.6) declare format of data buffer
    do
        if BUFFER_MODE == BUFFER_MODE_USE_VERTEX_BUFFER then
            -- (B.1) declaring a custom vertex buffer format
            -- if using mesh as a buffer, location needs to be appended to locations of drawMeshFormat
            perInstanceFormat = {
                {
                    location = 3,
                    name = "InstanceOffset",
                    format = "floatvec2"
                },

                {
                    location = 4,
                    name = "InstanceScale",
                    format = "float"
                },

                {
                    location = 5,
                    name = "InstanceHue",
                    format = "float"
                }
            }

        elseif BUFFER_MODE == BUFFER_MODE_USE_STORAGE_BUFFER then
            -- (C.1) declaring a custom storage buffer format
            -- if using storage buffer, locations start at 0
            perInstanceFormat = {
                {
                    location = 0,
                    name = "InstanceOffset",
                    format = "floatvec2"
                },

                {
                    location = 1,
                    name = "InstanceScale",
                    format = "float"
                },

                {
                    location = 2,
                    name = "InstanceHue",
                    format = "float"
                },
            }
        elseif BUFFER_MODE == BUFFER_MODE_USE_TEXEL_BUFFER then
            -- (D.1) declaring a custom texel buffer format
            -- if using texel buffer, all components need to have the same format
            local format = "float"
            perInstanceFormat = {
                {
                    location = 0,
                    name = "InstanceData",
                    format = "floatvec4" -- only 4-component are supported
                }
            }
        end
    end

    -- (A.2) initializing the draw mesh as circle
    do
        local nVertices = 16
        local drawMeshData = {}
        for i = 1, nVertices + 1 do
            local angle = (i - 1) / nVertices * (2 * math.pi)
            table.insert(drawMeshData, {
                math.cos(angle), -- Attribute #1: VertexPosition.x (x)
                math.sin(angle), -- Attribute #1: VertexPosition.y (y)
                math.cos(angle), -- Attribute #2: VertexTextureCoordinates.x (u)
                math.sin(angle), -- Attribute #2: VertexTextureCoordinates.y (v)
                1, -- Attribute #3: VertexColor.x (r)
                1, -- Attribute #3: VertexColor.y (g)
                1, -- Attribute #3: VertexColor.z (b)
                1, -- Attribute #3: VertexColor.w (a)
            })
        end
        table.insert(drawMeshData, 1,  { 0, 0, 0, 0, 1, 1, 1, 1 }) -- add center vertex

        drawMesh = love.graphics.newMesh(
            drawMeshFormat, -- vertex attribute format
            drawMeshData,   -- vertex data
            "fan",   -- draw mode
            "static" -- buffer usage
        )

        -- we use draw mode `fan` to correctly draw a filled circle
        -- we use buffer usage `static`, since `drawMesh` will never change, only the per-instance data will
    end

    -- (A.3) initializing the data buffer with per instance data

    local initialData = {}
    for instanceIndex = 1, instanceCount do
        local x, y = generateOffset(instanceIndex) -- 2 floats
        local scale = generateScale(instanceIndex) -- 1 float
        local hue = generateHue(instanceIndex)
        table.insert(initialData, {
            x, y,
            scale,
            hue
        })
    end
    
    -- (A.7) initializing the per-instance data CPU-side

    if DATA_MODE == DATA_MODE_USE_TABLES then
        -- (B.2)(C.2)(D.2) using lua tables as instance data
        -- keep `perInstanceData` as a table
        perInstanceData = initialData
    elseif DATA_MODE == DATA_MODE_USE_BYTE_DATA then
        -- (B.3)(C.3)(D.3) using `ByteData` as instance data
        -- instance size is `InstanceOffset` + `InstanceScale` + `InstanceHue`
        local stride = 2 * ffi.sizeof("float") + ffi.sizeof("float") + ffi.sizeof("float")

        -- data size is (number of instances) * (size per instance)
        local byteData = love.data.newByteData(instanceCount * stride)

        -- assign initial byte data
        local floatBytes = ffi.sizeof("float")
        for i, data in ipairs(initialData) do
            local byteOffset = (i - 1) * stride
            byteData:setFloat(byteOffset + 0 * floatBytes, data[1])
            byteData:setFloat(byteOffset + 1 * floatBytes, data[2])
            byteData:setFloat(byteOffset + 2 * floatBytes, data[3])
            byteData:setFloat(byteOffset + 3 * floatBytes, data[4])
        end

        -- use byte data as global data
        perInstanceData = byteData
    elseif DATA_MODE == DATA_MODE_USE_FFI_DATA then
        -- (B.4)(C.4)(D.4) using FFI data as instance data
        -- we need to allocate as `love.ByteData` anyway, even though we use ffi to modify it later
        local stride = 2 * ffi.sizeof("float") + ffi.sizeof("float") + ffi.sizeof("float")
        local byteData = love.data.newByteData(instanceCount * stride)

        -- assign initial byte data
        local floatBytes = ffi.sizeof("float")
        local byteDataPtr = ffi.cast("uint8_t*", byteData:getFFIPointer())

        for i, data in ipairs(initialData) do
            local byteOffset = (i - 1) * stride
            ffi.cast("float*", byteDataPtr + byteOffset + 0 * floatBytes)[0] = data[1]
            ffi.cast("float*", byteDataPtr + byteOffset + 1 * floatBytes)[0] = data[2]
            ffi.cast("float*", byteDataPtr + byteOffset + 2 * floatBytes)[0] = data[3]
            ffi.cast("float*", byteDataPtr + byteOffset + 3 * floatBytes)[0] = data[4]
        end

        perInstanceData = byteData
    end

    -- (A.4) initialize the graphics buffer

    if BUFFER_MODE == BUFFER_MODE_USE_VERTEX_BUFFER then
        -- (B.5) intantiating a vertex buffer
        -- usage mesh as storage buffer
        local perInstanceDataMesh = love.graphics.newMesh(
            perInstanceFormat,
            initialData,
            "points", -- draw mode unused
            "stream"
        )

        -- (B.6) attach the mesh to the draw mesh
        for _, entry in pairs(perInstanceFormat) do
            drawMesh:attachAttribute(entry.name, 
                perInstanceDataMesh, 
                "perinstance" -- 1 attribute per 1 instanced
            )
        end

        -- convert mesh to a buffer for love.update
        perInstanceDataBuffer = perInstanceDataMesh:getVertexBuffer()
    elseif BUFFER_MODE == BUFFER_MODE_USE_STORAGE_BUFFER then
        -- allocate the buffer directly
        perInstanceDataBuffer = love.graphics.newBuffer(
            perInstanceFormat, -- buffer format
            initialData,    -- initial buffer data
            { shaderstorage = true } -- declare as storage buffer
        )

        local dummy = {}
        for _ = 1, perInstanceDataBuffer:getElementCount() do table.insert(dummy, {}) end

        local mesh = love.graphics.newMesh(perInstanceDataBuffer:getFormat(), {{}}, "triangles", "dynamic")
        mesh:setVertices(love.graphics.readbackBuffer(perInstanceDataBuffer))

    elseif BUFFER_MODE == BUFFER_MODE_USE_TEXEL_BUFFER then
        perInstanceDataBuffer = love.graphics.newBuffer(
            perInstanceFormat,
            initialData,
            { texel = true } -- declare as texel buffer
        )
    end

    -- (A.8) initialize the shader

    if BUFFER_MODE == BUFFER_MODE_USE_VERTEX_BUFFER then
        drawShader = love.graphics.newShader([[
#ifdef VERTEX // vertex shader

// draw mesh attributes
layout (location = 0) in vec2 VertexPosition;      // drawMesh attribute #1
layout (location = 1) in vec2 VertexTextureCoords; // drawMesh attribute #2
layout (location = 2) in vec4 VertexColor;         // drawMesh attribute #3

// (B.7) data mesh attributes
layout (location = 3) in vec2 InstanceOffset;    // perInstanceDataBuffer attribute #1
layout (location = 4) in float InstanceScale;    // perInstanceDataBuffer attribute #2
layout (location = 5) in float hue;              // perInstanceDataBuffer attribute #3

out vec2 FragmentTextureCoords; // final interpolated texture coordinates, for fragment shader
out vec4 FragmentColor;         // final interpolated color, for fragment shader

void vertexmain() { // custom vertex shader entry point
    // (A.5)
    // compute position from custom vertex attributes
    vec2 position = VertexPosition;
    position.xy *= InstanceScale;
    position.xy += InstanceOffset;

    // set texture coords to default value
    FragmentTextureCoords = VertexTextureCoords; // xy = uv

    // set color to default value
    FragmentColor = ConstantColor * vec4(VertexColor.rgb, VertexColor.a * hue);

    // set position
    love_Position = TransformProjectionMatrix * vec4(position.xy, 0.0, 1.0);
    // where `TransformProjectionMatrix` is a hardcoded global that holds the `love.graphics` Transform
    // and `love_Position` is a hardcoded global variable that holds the position of a vertex, in px
}

#endif

#ifdef PIXEL // fragment shader

in vec2 FragmentTextureCoords; // texture coords from vertex shader
in vec4 FragmentColor;         // color from vertex shader

out vec4 FinalColor; // final fragment color drawn to the screen at love_Position

uniform sampler2D InstanceTexture; // texture of the instance mesh

void pixelmain() { // custom fragment shader entry point
    // default behavior of `effect`, implemented manually
    FinalColor = FragmentColor * texture(InstanceTexture, FragmentTextureCoords);
}

#endif
]])
    elseif BUFFER_MODE == BUFFER_MODE_USE_STORAGE_BUFFER then
        drawShader = love.graphics.newShader([[
#pragma language glsl4

#ifdef VERTEX // vertex shader

// draw mesh attributes
layout (location = 0) in vec2 VertexPosition;
layout (location = 1) in vec2 VertexTextureCoords;
layout (location = 2) in vec4 VertexColor;

out vec2 FragmentTextureCoords;
out vec4 FragmentColor;

// (C.5) new; storage buffer
struct InstanceData {
    vec2 offset;
    float scale;
    float hue;
};

// (C.6) declare assignable storage buffer
readonly layout(std430, binding = 0) buffer perInstanceDataBuffer {
    InstanceData data[];
};

void vertexmain() {
    // (C.7) access per-instance data using instance ID
    InstanceData instanceData = data[gl_InstanceID];

    vec2 position = VertexPosition;
    position.xy *= instanceData.scale;
    position.xy += instanceData.offset;

    FragmentTextureCoords = VertexTextureCoords;
    FragmentColor = ConstantColor * vec4(VertexColor.rgb, VertexColor.a * instanceData.hue);

    love_Position = TransformProjectionMatrix * vec4(position.xy, 0.0, 1.0);
}

#endif

#ifdef PIXEL

in vec2 FragmentTextureCoords;
in vec4 FragmentColor;

out vec4 FinalColor;
uniform sampler2D InstanceTexture;

void pixelmain() {
    FinalColor = FragmentColor * texture(InstanceTexture, FragmentTextureCoords);
}

#endif
]])
    elseif BUFFER_MODE == BUFFER_MODE_USE_TEXEL_BUFFER then
        drawShader = love.graphics.newShader([[
#ifdef VERTEX // vertex shader

// draw mesh attributes
layout (location = 0) in vec2 VertexPosition;
layout (location = 1) in vec2 VertexTextureCoords;
layout (location = 2) in vec4 VertexColor;

// no per-instance attributes

out vec2 FragmentTextureCoords;
out vec4 FragmentColor;

// (D.6) new: texel buffer
uniform samplerBuffer perInstanceDataBuffer;

void vertexmain() {
    // (D.7) using instance id to access per-instance data
    // we use texelFetch to prevent interpolation
    vec4 instanceData = texelFetch(perInstanceDataBuffer, gl_InstanceID);
    vec2 instanceOffset = instanceData.xy;
    float instanceScale = instanceData.z;
    float instanceHue = instanceData.w;

    vec2 position = VertexPosition;
    position.xy *= instanceScale;
    position.xy += instanceOffset;

    FragmentTextureCoords = VertexTextureCoords;
    FragmentColor = ConstantColor * vec4(VertexColor.rgb, VertexColor.a * instanceHue);

    love_Position = TransformProjectionMatrix * vec4(position.xy, 0.0, 1.0);
}

#endif

#ifdef PIXEL

in vec2 FragmentTextureCoords;
in vec4 FragmentColor;

out vec4 FinalColor;
uniform sampler2D InstanceTexture;

void pixelmain() {
    FinalColor = FragmentColor * texture(InstanceTexture, FragmentTextureCoords);
}

#endif
]])
    end
end -- love.load

--  draw loop
love.draw = function()
    love.graphics.clear()

    -- store graphics state, including shader, color, etc.
    love.graphics.push("all")

    -- (A.4) bind shader
    love.graphics.setShader(drawShader)

    -- assign the draw mesh texture if present
    if drawMesh:getTexture() ~= nil then
        drawShader:send("drawTexture", drawMesh:getTexture())
    end

    -- assign the storage / texel buffer if present
    if drawShader:hasUniform("perInstanceDataBuffer") then
        -- (C.8)(D.5) make the buffer accessible from within the shader
        drawShader:send("perInstanceDataBuffer", perInstanceDataBuffer)
    end

    -- set color / transform
    love.graphics.setColor(1, 1, 1, 1)

    -- (A.3)
    -- draw `instanceCount` many copies of the mesh instanced
    -- each instance will read the correct data using the vertex shader
    love.graphics.drawInstanced(drawMesh, instanceCount)

    -- unbind shader, etc.
    love.graphics.pop() -- all

    love.graphics.print("# Particles: " .. instanceCount .. " | FPS: " .. love.timer.getFPS(), 5, 5)
end

-- update loop

love.update = function()
    -- modify the per-instance data

    if DATA_MODE == DATA_MODE_USE_TABLES then
        -- `perInstanceData` is a simple table, modify it using regular lua

        local offsetX = 1   -- per-instance #1 component #1: InstanceOffset.x
        local offsetY = 2   -- per-instance #1 component #2: InstanceOffset.y
        local scale = 3     -- per-instance attribute #2 component #1: InstanceScale.x
        local hue = 4       -- per-instance attribute #3 component #1: InstanceHue.x

        -- TODO modify the Lua table directly
        for instanceIndex = 1, instanceCount do
            -- extract per-instance data
            local instanceData = perInstanceData[instanceIndex]

            -- write new per-instance attributes to CPU-side copy of instance data
            instanceData[offsetX], instanceData[offsetY] = modifyOffset(instanceIndex,
                instanceData[offsetX],
                instanceData[offsetY]
            )

            instanceData[scale] = modifyScale(instanceIndex,
                instanceData[scale]
            )

            instanceData[hue] = modifyHue(instanceIndex,
                instanceData[hue]
            )
        end
    elseif DATA_MODE == DATA_MODE_USE_BYTE_DATA then
        -- `perInstanceData` is a `love.ByteDatA`, use `set*` / `get*`

        -- get the size of one instance data element, in bytes
        local stride = perInstanceDataBuffer:getElementStride()

        -- TODO modify the byte data using its internal methods
        local offset = 0
        for instanceIndex = 1, instanceCount do
            local startOffset = offset

            -- read per-instance properties from byte data
            local readOffset = startOffset

            local x = perInstanceData:getFloat(readOffset)
            readOffset = readOffset + ffi.sizeof("float")

            local y = perInstanceData:getFloat(readOffset)
            readOffset = readOffset + ffi.sizeof("float")

            local scale = perInstanceData:getFloat(readOffset)
            readOffset = readOffset + ffi.sizeof("float")

            local hue = perInstanceData:getFloat(readOffset)
            readOffset = readOffset + ffi.sizeof("float")

            -- mutate
            x, y = modifyOffset(instanceIndex, x, y)
            scale = modifyScale(instanceIndex, scale)
            hue = modifyHue(instanceIndex, hue)

            -- write per-instance properties to byte data
            local writeOffset = startOffset

            perInstanceData:setFloat(writeOffset, x)
            writeOffset = writeOffset + ffi.sizeof("float")

            perInstanceData:setFloat(writeOffset, y)
            writeOffset = writeOffset + ffi.sizeof("float")

            perInstanceData:setFloat(writeOffset, scale)
            writeOffset = writeOffset + ffi.sizeof("float")

            perInstanceData:setFloat(writeOffset, hue)
            writeOffset = writeOffset + ffi.sizeof("float")

            offset = offset + stride
        end

    elseif DATA_MODE == DATA_MODE_USE_FFI_DATA then
        -- cast to 8-bit array so we can use byte offsets as before
        local perInstanceDataPtr = ffi.cast("uint8_t*", perInstanceData:getFFIPointer())

        -- get the size of one instance data element, in bytes
        local stride = perInstanceDataBuffer:getElementStride()

        -- TODO modify the C data using FFI
        local offset = 0
        for instanceIndex = 1, instanceCount do
            local startOffset = offset

            -- read per-instance properties from byte data
            local readOffset = startOffset

            -- cast the byte pointer at this offset to the appropriate type pointer, then dereference using `[0]`
            local x = ffi.cast("float*", perInstanceDataPtr + readOffset)[0]
            readOffset = readOffset + ffi.sizeof("float")

            local y = ffi.cast("float*", perInstanceDataPtr + readOffset)[0]
            readOffset = readOffset + ffi.sizeof("float")

            local scale = ffi.cast("float*", perInstanceDataPtr + readOffset)[0]
            readOffset = readOffset + ffi.sizeof("float")

            local hue = ffi.cast("float*", perInstanceDataPtr + readOffset)[0]
            readOffset = readOffset + ffi.sizeof("float")

            -- mutate
            x, y = modifyOffset(instanceIndex, x, y)
            scale = modifyScale(instanceIndex, scale)
            hue = modifyHue(instanceIndex, hue)

            -- write per-instance properties to byte data
            local writeOffset = startOffset

            ffi.cast("float*", perInstanceDataPtr + writeOffset)[0] = x
            writeOffset = writeOffset + ffi.sizeof("float")

            ffi.cast("float*", perInstanceDataPtr + writeOffset)[0] = y
            writeOffset = writeOffset + ffi.sizeof("float")

            ffi.cast("float*", perInstanceDataPtr + writeOffset)[0] = scale
            writeOffset = writeOffset + ffi.sizeof("float")

            ffi.cast("float*", perInstanceDataPtr + writeOffset)[0] = hue
            writeOffset = writeOffset + ffi.sizeof("float")

            offset = offset + stride

            -- these casts have a performance impact, we should instead cast once outside the loop. Here they are
            -- used inside the loop her for the sake of matching the `DATA_MODE_USE_BYTE_DATA` loop 1:1 for
            -- pedagogic purposes only
        end
    end

    -- TODO update the per-instance data buffer
    perInstanceDataBuffer:setArrayData(perInstanceData)
end

-- ### INTERNALS ###

generateOffset = function(instanceIndex)
    local xMargin, yMargin = 0.25 * love.graphics.getWidth(), 0.25 * love.graphics.getHeight()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    local xCenter, yCenter = w / 2, h / 2
    local stddev = math.min((w - 2 * xMargin) / 6, (h - 2 * yMargin) / 6)

    local x = love.math.randomNormal(stddev, xCenter)
    local y = love.math.randomNormal(stddev, yCenter)

    x = math.max(xMargin, math.min(w - xMargin, x))
    y = math.max(yMargin, math.min(h - yMargin, y))

    return x, y
end

generateScale = function(instanceIndex)
    return love.math.random(1, 8)
end

generateHue = function(instanceIndex)
    local lower, upper = 0.06, 0.3
    local t = love.math.random()
    return lower * t + upper * (1 - t)
end

modifyOffset = function(instanceIndex, x, y)
    local maxOffset = 100 * love.timer.getDelta()
    local t = love.timer.getTime()

    local seedX = instanceIndex * 17.3
    local seedY = -instanceIndex * 31.1777777
    local newX = x + maxOffset * (love.math.perlinNoise(seedX, t) * 2 - 1)
    local newY = y + maxOffset * (love.math.perlinNoise(seedY, t) * 2 - 1)

    local minX, maxX = 0, love.graphics.getWidth()
    local minY, maxY = 0, love.graphics.getHeight()

    if newX < minX then
        newX = minX + (minX - newX)
    elseif newX > maxX then
        newX = maxX - (newX - maxX)
    end

    if newY < minY then
        newY = minY + (minY - newY)
    elseif newY > maxY then
        newY = maxY - (newY - maxY)
    end

    return newX, newY
end

modifyScale = function(instanceIndex, scale)
    return 1 + 9 * (math.sin(love.timer.getTime() + (instanceIndex / instanceCount) * (2 * math.pi)) + 1) / 2
end

modifyHue = function(instanceIndex, hue)
    return hue
end
```



