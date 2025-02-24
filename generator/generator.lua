--------------------------------------------------------------------------
--script for auto_funcs.h and auto_funcs.cpp generation
--expects LuaJIT
--------------------------------------------------------------------------
assert(_VERSION=='Lua 5.1',"Must use LuaJIT")
assert(bit,"Must use LuaJIT")
local script_args = {...}
local COMPILER = script_args[1]
local INTERNAL_GENERATION = (script_args[2] and script_args[2]:match("internal")) and true or false
local CPRE,CTEST
if COMPILER == "gcc" or COMPILER == "clang" then
    CPRE = COMPILER..[[ -E -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMPLOT_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_API="" -DIMGUI_IMPL_API="" ]]
    CTEST = COMPILER.." --version"
elseif COMPILER == "cl" then
    CPRE = COMPILER..[[ /E /DIMGUI_DISABLE_OBSOLETE_FUNCTIONS /DIMPLOT_DISABLE_OBSOLETE_FUNCTIONS /DIMGUI_API="" /DIMGUI_IMPL_API="" ]]
    CTEST = COMPILER
else
    print("Working without compiler ")
	error("cant work with "..COMPILER.." compiler")
end
--test compiler present
local HAVE_COMPILER = false

local pipe,err = io.popen(CTEST,"r")
if pipe then
    local str = pipe:read"*a"
    print(str)
    pipe:close()
    if str=="" then
        HAVE_COMPILER = false
    else
        HAVE_COMPILER = true
    end
else
    HAVE_COMPILER = false
    print(err)
end
assert(HAVE_COMPILER,"gcc, clang or cl needed to run script")


print("HAVE_COMPILER",HAVE_COMPILER)
print("INTERNAL_GENERATION",INTERNAL_GENERATION)
--------------------------------------------------------------------------
--this table has the functions to be skipped in generation
--------------------------------------------------------------------------
local cimgui_manuals = {
     --ImPlot_PlotLineG = true,
}
local cimgui_skipped = {
	 --ImPlot_AnnotateClamped = true
}
--------------------------------------------------------------------------
--this table is a dictionary to force a naming of function overloading (instead of algorythmic generated)
--first level is cimguiname without postfix, second level is the signature of the function, value is the
--desired name
---------------------------------------------------------------------------
local cimgui_overloads = {
    --igPushID = {
        --["(const char*)"] =           "igPushIDStr",
        --["(const char*,const char*)"] = "igPushIDRange",
        --["(const void*)"] =           "igPushIDPtr",
        --["(int)"] =                   "igPushIDInt"
    --},
}

--------------------------header definitions
local cimgui_header = 
[[//This file is automatically generated by generator.lua from https://github.com/cimgui/cimplot
//based on implot.h file version XXX from implot https://github.com/epezent/implot
]]

if INTERNAL_GENERATION then
	cimgui_header = cimgui_header..[[//with implot_internal.h api
]]
end
--------------------------------------------------------------------------
--helper functions
--------------------------------functions for C generation
--load parser module
package.path = package.path .. ";../../cimgui/generator/?.lua"
local cpp2ffi = require"cpp2ffi"
local read_data = cpp2ffi.read_data
local save_data = cpp2ffi.save_data
local copyfile = cpp2ffi.copyfile
local serializeTableF = cpp2ffi.serializeTableF

local func_header_generate = cpp2ffi.func_header_generate
local func_implementation = cpp2ffi.func_implementation

----------custom ImVector templates (from cimgui, but removed need to separate pool as ImGuiStorage already declared in cimgui)
local table_do_sorted = cpp2ffi.table_do_sorted

--generate cimgui.cpp cimgui.h 
local function cimgui_generation(parser,name)

    local hstrfile = read_data("./"..name.."_template.h")

	local outpre,outpost = parser.structs_and_enums[1], parser.structs_and_enums[2]

	cpp2ffi.prtable(parser.templates)
	cpp2ffi.prtable(parser.typenames)

	local tdt = parser:generate_templates()

	local cstructsstr = outpre..tdt..outpost 

    hstrfile = hstrfile:gsub([[#include "imgui_structs%.h"]],cstructsstr)
    local cfuncsstr = func_header_generate(parser)
    hstrfile = hstrfile:gsub([[#include "auto_funcs%.h"]],cfuncsstr)
    save_data("./output/"..name..".h",cimgui_header,hstrfile)
    
    --merge it in cimplot_template.cpp to cimplot.cpp
    local cimplem = func_implementation(parser)

    local hstrfile = read_data("./"..name.."_template.cpp")

    hstrfile = hstrfile:gsub([[#include "auto_funcs%.cpp"]],cimplem)
    save_data("./output/"..name..".cpp",cimgui_header,hstrfile)

end
--------------------------------------------------------
-----------------------------do it----------------------
--------------------------------------------------------
--get implot.h version--------------------------
local pipe,err = io.open("../implot/implot.h","r")
if not pipe then
    error("could not open file:"..err)
end
local implot_version
while true do
    local line = pipe:read"*l"
    implot_version = line:match([[ImPlot%s+v(.+)]])
    if implot_version then break end
end
pipe:close()
cimgui_header = cimgui_header:gsub("XXX",implot_version)
print("IMPLOT_VERSION",implot_version)

----------------------------------custom generators for implot_PlotXXXXG
--functions having ImPlotGetter

local function custom_header(outtab, def)
	if not def.args:match"ImPlotGetter " then return false end
	local args = def.args:gsub("ImPlotGetter","ImPlotPoint_getter")
	table.insert(outtab,"CIMGUI_API "..def.ret.." ".. def.ov_cimguiname ..args..";//custom generation\n")
	return true
end
local function custom_implementation(outtab,def)
	if not def.args:match"ImPlotGetter " then return false end
	local args = def.args:gsub("ImPlotGetter","ImPlotPoint_getter")
    table.insert(outtab,"CIMGUI_API".." "..def.ret.." "..def.ov_cimguiname..args.."\n")
    table.insert(outtab,"{\n")
	local ngetter = 0
	local call_args = "("
	for i,arg in ipairs(def.argsT) do
		if arg.type == "ImPlotGetter" then
			arg.custom_type = "ImPlotPoint_getter"
			ngetter = ngetter + 1
			table.insert(outtab,"    getter_funcX"..((ngetter==1 and "") or (ngetter==2 and "2") or error"too much getters").." = "..arg.name..";\n")
			call_args = call_args..((ngetter==1 and "Wrapper,") or (ngetter==2 and "Wrapper2,"))
		else
			call_args = call_args..arg.name..","
		end
	end
	call_args = call_args:sub(1,-2)..")"
	table.insert(outtab,"    ImPlot::"..def.funcname..call_args..";\n")
    table.insert(outtab,"}\n")
	return true
end
-------------funtion for parsing implot headers
local function parseImGuiHeader(header,names)
	--prepare parser
	local parser = cpp2ffi.Parser()
	parser.getCname = function(stname,funcname,namespace)
		--local pre = (stname == "") and "ImPlot_" or stname.."_"
		--local pre = (stname == "") and (namespace and (namespace=="ImGui" and "ig" or namespace.."_") or "ig") or stname.."_"
		local pre = (stname == "") and (namespace and (namespace=="ImGui" and "ig" or namespace.."_") or "ImPlot_") or stname.."_"
		return pre..funcname
	end
	parser.cname_overloads = cimgui_overloads
	parser.manuals = cimgui_manuals
	parser.skipped = cimgui_skipped
	parser.UDTs = {"ImVec2","ImVec4","ImColor","ImPlotRect","ImPlotPoint","ImPlotLimits","ImPlotTime"}
	--parser.gentemplatetypedef = gentemplatetypedef
	parser.cimgui_inherited =  dofile([[../../cimgui/generator/output/structs_and_enums.lua]])
	--this list will expand all templated functions
	parser.ftemplate_list = {}
	parser.ftemplate_list.T = {"float", "double", "ImS8", "ImU8", "ImS16", "ImU16", "ImS32", "ImU32", "ImS64", "ImU64"}
	
	parser.custom_implementation = custom_implementation
	parser.custom_header = custom_header
	
	parser:take_lines(CPRE..header, names, COMPILER)
	
	return parser
end
--generation
print("------------------generation with "..COMPILER.."------------------------")
local modulename = "cimplot"
local headers = [[#include "../implot/implot.h" 
]]
local headersT = {[[implot]]}
if INTERNAL_GENERATION then
    headers = headers .. [[#include "../implot/implot_internal.h"
	]]
	headersT[#headersT + 1] = [[implot_internal]]
end

save_data("headers.h",headers)
local include_cmd = COMPILER=="cl" and [[ /I ]] or [[ -I ]]
local extra_includes = include_cmd.." ../../cimgui/imgui "
local parser1 = parseImGuiHeader(extra_includes .. [[headers.h]],headersT)
os.remove("headers.h")
parser1:do_parse()

save_data("./output/overloads.txt",parser1.overloadstxt)
cimgui_generation(parser1,modulename)
save_data("./output/definitions.lua",serializeTableF(parser1.defsT))
local structs_and_enums_table = parser1.structs_and_enums_table
save_data("./output/structs_and_enums.lua",serializeTableF(structs_and_enums_table))
save_data("./output/typedefs_dict.lua",serializeTableF(parser1.typedefs_dict))

-------------------------------json saving
--avoid mixed tables (with string and integer keys)
local function json_prepare(defs)
    --delete signatures in function
    for k,def in pairs(defs) do
        for k2,v in pairs(def) do
            if type(k2)=="string" then
                def[k2] = nil
            end
        end
    end
    return defs
end
---[[
local json = require"json"
local json_opts = {dict_on_empty={defaults=true}}
save_data("./output/definitions.json",json.encode(json_prepare(parser1.defsT),json_opts))
save_data("./output/structs_and_enums.json",json.encode(structs_and_enums_table))
save_data("./output/typedefs_dict.json",json.encode(parser1.typedefs_dict))
--]]
-------------------copy C files to repo root
copyfile("./output/"..modulename..".h", "../"..modulename..".h")
copyfile("./output/"..modulename..".cpp", "../"..modulename..".cpp")
print"all done!!"
