---
title: "Meshes"
authors: [clemapfel]
date: 2026-07-14
---

# Meshes

This chapter will cover **Meshes**, which are a central concept in graphics programming and are used to display any geometry on screen. While rarely used by beginners thanks to LÖVEs high level of abstraction, meshes are actually used internally by LÖVE for displaying any kind of graphics, including for `love.graphics.rectangle`, `love.graphics.circle`, `love.graphics.polygon`, and `draw`ing `Images`, `SpriteBatche`s, `ParticleSystem`s, etc.

By mastering meshes, we can extend LÖVEs graphical capability significantly, rendering shapes not possible with LÖVEs existing high-level API, and achieving performance even better what basic usage of LÖVE can offer.

## Table of Contents

---

# 0. TL;DR: Quick Start

Given here are code snippets that illustrate basic usage of meshes. These are **intended to be referenced after having read this chapter**. Readers new to meshes are not expected to understand these snippets, and should [skip to section 1 of this chapter](#10-what-are-meshes-why-use-them).

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

# 1.0 What Are Meshes? Why use them?
## 1.1 Vertices
## 1.2 Vertex Attributes: Mesh Vertex Format, Vertex Data
### 1.2.1 Vertex Position
### 1.2.2 Vertex Texture Coordinates (UV)
### 1.2.3 Vertex Color
### 1.2.4 Custom Vertex Attributes
### 1.2.5 Vertex Attribute Formats
## 1.3 Mesh Draw Modes
### 1.3.1 Draw Mode: `"fan"`
### 1.3.1 Draw Mode: `"strip"`
### 1.3.1 Draw Mode: `"triangles"`
### 1.3.1 Draw Mode: `"points"`
## 1.4 Index Buffers & setVertexMap
## 1.5 Graphics Buffer Usage
## 1.6 Creating the Mesh
## 1.7 Updating Vertex Data
### 1.7.1 `setVertexAttribute`
### 1.7.2 `setVertices`
### 1.7.3 Using `ByteData`
# 2.0 Geometry Instancing
## 2.1 Attribute Attachment
## 2.2 Instanced Drawing
