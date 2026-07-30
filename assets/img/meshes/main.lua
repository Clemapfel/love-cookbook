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

    -- (x.0) declare vertex attribute format of draw mesh
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

    -- (x.1) declare format of data buffer

    do
        if BUFFER_MODE == BUFFER_MODE_USE_VERTEX_BUFFER then
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

    -- (x.1) initialize draw mesh as circle
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

    -- (x.2) initialize the data buffer with per instance data

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

    if DATA_MODE == DATA_MODE_USE_TABLES then
        -- keep `perInstanceData` as a table
        perInstanceData = initialData
    elseif DATA_MODE == DATA_MODE_USE_BYTE_DATA then
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

    -- (x.3) initialize the graphics buffer

    if BUFFER_MODE == BUFFER_MODE_USE_VERTEX_BUFFER then
        -- usage mesh as storage buffer
        local perInstanceDataMesh = love.graphics.newMesh(
            perInstanceFormat,
            initialData,
            "points", -- draw mode unused
            "stream"
        )

        -- attach the mesh to the draw mesh
        for _, entry in pairs(perInstanceFormat) do
            drawMesh:attachAttribute(entry.name, perInstanceDataMesh, "perinstance")
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
    elseif BUFFER_MODE == BUFFER_MODE_USE_TEXEL_BUFFER then
        perInstanceDataBuffer = love.graphics.newBuffer(
            perInstanceFormat,
            initialData,
            { texel = true } -- declare as texel buffer
        )
    end

    -- (x.4) initialize the shader

    if BUFFER_MODE == BUFFER_MODE_USE_VERTEX_BUFFER then
        drawShader = love.graphics.newShader([[
#ifdef VERTEX // vertex shader

// draw mesh attributes
layout (location = 0) in vec2 VertexPosition;      // drawMesh attribute #1
layout (location = 1) in vec2 VertexTextureCoords; // drawMesh attribute #2
layout (location = 2) in vec4 VertexColor;         // drawMesh attribute #3

// data mesh attributes
layout (location = 3) in vec2 InstanceOffset;    // perInstanceDataBuffer attribute #1
layout (location = 4) in float InstanceScale;    // perInstanceDataBuffer attribute #2
layout (location = 5) in float hue;              // perInstanceDataBuffer attribute #3

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

// new; storage buffer
struct InstanceData {
    vec2 offset;
    float scale;
    float hue;
};

readonly layout(std430, binding = 0) buffer perInstanceDataBuffer {
    InstanceData data[];
};

void vertexmain() {
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

// new: texel buffer
uniform samplerBuffer perInstanceDataBuffer;

void vertexmain() {
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

-- (x.1) draw loop
love.draw = function()
    love.graphics.clear()

    -- store graphics state, including shader, color, etc.
    love.graphics.push("all")

    -- bind shader
    love.graphics.setShader(drawShader)

    -- assign the draw mesh texture if present
    if drawMesh:getTexture() ~= nil then
        drawShader:send("drawTexture", drawMesh:getTexture())
    end

    -- assign the storage / texel buffer if present
    if drawShader:hasUniform("perInstanceDataBuffer") then
        drawShader:send("perInstanceDataBuffer", perInstanceDataBuffer)
    end

    -- set color / transform
    love.graphics.setColor(1, 1, 1, 1)

    -- draw `instanceCount` many copies of the mesh instanced
    -- each instance will read the correct data using the vertex shader
    love.graphics.drawInstanced(drawMesh, instanceCount)

    -- unbind shader, etc.
    love.graphics.pop() -- all

    love.graphics.print("# Particles: " .. instanceCount .. " | FPS: " .. love.timer.getFPS(), 5, 5)
end

-- (x.2) update loop

love.update = function()
    -- modify the per-instance data

    if DATA_MODE == DATA_MODE_USE_TABLES then
        -- `perInstanceData` is a simple table, modify it using regular lua

        local offsetX = 1   -- per-instance #1 component #1: InstanceOffset.x
        local offsetY = 2   -- per-instance #1 component #2: InstanceOffset.y
        local scale = 3     -- per-instance attribute #2 component #1: InstanceScale.x
        local hue = 4       -- per-instance attribute #3 component #1: InstanceHue.x

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
        end
    end

    -- update the per-instance data buffer
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
