local lpeg = require 'lpeglabel'
local re = require 'nelua.thirdparty.relabel'
local class = require 'nelua.utils.class'
local tabler = require 'nelua.utils.tabler'
local errorer = require 'nelua.utils.errorer'
local pegger = require 'nelua.utils.pegger'
local metamagic = require 'nelua.utils.metamagic'
local except = require 'nelua.utils.except'
local nanotimer = require 'nelua.utils.nanotimer'
local console = require 'nelua.utils.console'
local config = require 'nelua.configer'.get()
local ASTNode = require 'nelua.astnode'

local PEGParser = class()

lpeg.setmaxstack(1024)
PEGParser.working_time = 0

function PEGParser:_init()
  self.keywords = {}
  self.syntax_errors = {}
  self.defs = {}
  self.pegdescs = {}
end

local function inherit_defs(parent_defs, defs)
  if defs then
    metamagic.setmetaindex(defs, parent_defs, true)
    return defs
  else
    return parent_defs
  end
end

local function recompile_peg(selfdefs, pegdesc)
  local combined_defs = inherit_defs(selfdefs, pegdesc.defs)
  local compiled_patt = re.compile(pegdesc.patt, combined_defs)
  if pegdesc.modf then
    compiled_patt = pegdesc.modf(compiled_patt, selfdefs)
  end
  selfdefs[pegdesc.name] = compiled_patt
end


function PEGParser:set_astbuilder(astbuilder)
  self.astbuilder = astbuilder
  local astnodes = astbuilder.nodes
  local unpack = table.unpack

  local to_astnode = ASTNode.make_toastnode(self, astnodes)

  local defs = self.defs
  defs.to_astnode = to_astnode
  defs.to_chain_unary_op = function(...)
    local expr, endpos = select(-2, ...)
    for i=select('#',...)-3,0,-2 do
      local pos, opname = select(i, ...)
      expr = to_astnode(pos, 'UnaryOp', opname, expr, endpos)
    end
    return expr
  end

  defs.to_list_astnode = function(pos, tag, exprs, endpos)
    if #exprs == 1 then
      return exprs[1]
    end
    return to_astnode(pos, tag, exprs, endpos)
  end

  defs.to_chain_late_unary_op = function(...)
    local expr, endpos = select(-2, ...)
    for i=select('#',...)-2,1,-1 do
      local op = select(i,...)
      op[3] = expr
      op[#op+1] = endpos
      expr = to_astnode(unpack(op))
    end
    return expr
  end

  defs.to_binary_op = function(pos, lhs, opname, rhs, endpos)
    if not rhs then
      return lhs
    end
    return to_astnode(pos, 'BinaryOp', opname, lhs, rhs, endpos)
  end

  defs.to_chain_binary_op = function(pos, lhs, ...)
    if ... then
      for i=1,select('#',...),3 do
        local opname, rhs, endpos = select(i, ...)
        lhs = to_astnode(pos, 'BinaryOp', opname, lhs, rhs, endpos)
      end
    end
    return lhs
  end

  defs.to_chain_index_or_call = function(last_expr, ...)
    for i=1,select('#',...) do
      local expr = select(i, ...)
      local n = #expr
      expr[n], expr[n+1] = last_expr, expr[n]
      last_expr = to_astnode(unpack(expr))
    end
    return last_expr
  end

  defs.to_nil = function() return nil end
  defs.to_true = function() return true end
  defs.to_false = function() return false end

  for _,pegdesc in pairs(self.pegdescs) do
    recompile_peg(defs, pegdesc)
  end
end

local function get_peg_deps(patt, defs, full_defs)
  if not defs then return {} end
  local deps = {}
  local proxy_defs = {}
  metamagic.setmetaindex(proxy_defs,
    function(_, name)
      if defs[name] then
        table.insert(deps, name)
      end
      return full_defs[name]
    end)
  re.compile(patt, proxy_defs)
  return deps
end

local function cascade_dependencies_for(pegdescs, name, list)
  list = list or {}
  for pegname,pegdesc in pairs(pegdescs) do
    if pegdesc.deps then
      for _,depname in ipairs(pegdesc.deps) do
        if depname == name and not list[pegname] then
          list[pegname] = true
          table.insert(list, pegdesc)
          cascade_dependencies_for(pegdescs, pegname, list)
        end
      end
    end
  end
  return list
end

local function recompile_dependencies_for(self, name)
  local to_recompile = cascade_dependencies_for(self.pegdescs, name)
  for _,pegdesc in ipairs(to_recompile) do
    recompile_peg(self.defs, pegdesc)
  end
end

function PEGParser:set_peg(name, patt, defs, modf)
  local combined_defs = inherit_defs(self.defs, defs)
  local compiled_patt = re.compile(patt, combined_defs)
  local deps = get_peg_deps(patt, self.defs, combined_defs)
  if modf then
    compiled_patt = modf(compiled_patt, self.defs)
  end
  local must_recompile = (self.defs[name] ~= nil)
  self.defs[name] = compiled_patt
  self.pegdescs[name] = {
    name = name,
    patt = patt,
    defs = defs,
    modf = modf,
    deps = deps
  }
  if must_recompile then
    recompile_dependencies_for(self, name)
  end
end

function PEGParser:remove_peg(name)
  errorer.assertf(self.defs[name], 'cannot remove non existent peg "%s"', name)
  local refs = cascade_dependencies_for(self.pegdescs, name)
  errorer.assertf(#refs == 0, 'cannot remove peg "%s" that has references', name)
  self.defs[name] = nil
  self.pegdescs[name] = nil
end

function PEGParser:set_pegs(combined_patts, defs, modf)
  local pattdescs = pegger.split_grammar_extern_patts(combined_patts)
  for _,pattdesc in ipairs(pattdescs) do
    local patt = string.format('%s <- %s', pattdesc.name, pattdesc.patt)
    self:set_peg(pattdesc.name, patt, defs, modf)
  end
end

function PEGParser:match(pegname, srccontent, srcname)
  local peg = self.defs[pegname]
  errorer.assertf(peg, 'cannot match an input to inexistent peg "%s"', pegname)
  self.src = {content=srccontent, name=srcname}
  local timer
  if config.timing or config.more_timing then
    timer = nanotimer()
  end
  local res, errlabel, errpos = peg:match(srccontent)
  if timer then
    local elapsed = timer:elapsed()
    PEGParser.working_time = PEGParser.working_time + elapsed
    if config.more_timing then
      console.debugf('parsed %s (%.1f ms)', srcname, elapsed)
    end
  end
  self.src = nil
  return res, errlabel, errpos
end

local function token_peg_generator(p, defs)
  return p * defs.SKIP
end

function PEGParser:set_token_peg(name, patt, defs)
  assert(self.defs.SKIP, 'cannot set token without a SKIP peg')
  return self:set_peg(name, patt, defs, token_peg_generator)
end

function PEGParser:set_token_pegs(combined_peg, defs)
  assert(self.defs.SKIP, 'cannot set token without a SKIP peg')
  return self:set_pegs(combined_peg, defs, token_peg_generator)
end

local function recompile_keyword_peg(self)
  local keyword_names = tabler.imap(self.keywords, function(v) return v:upper() end)
  local keyword_patt = string.format('%%%s', table.concat(keyword_names, '/%'))
  self:set_token_peg('KEYWORD', keyword_patt)
end

local function internal_add_keyword(self, keyword)
  local keyword_name = keyword:upper()
  assert(self.defs.IDSUFFIX, 'cannot add keyword without a IDSUFFIX peg')
  errorer.assertf(tabler.ifind(self.keywords, keyword) == nil, 'keyword "%s" already exists', keyword)
  table.insert(self.keywords, keyword)
  self:set_token_peg(keyword_name, string.format("'%s' !%%IDSUFFIX", keyword))
end

function PEGParser:add_keyword(keyword)
  internal_add_keyword(self, keyword)
  recompile_keyword_peg(self)
end

function PEGParser:remove_keyword(keyword)
  local keyword_name = keyword:upper()
  local i = tabler.ifind(self.keywords, keyword)
  errorer.assertf(i, 'keyword "%s" to remove not found', keyword)
  table.remove(self.keywords, i)
  recompile_keyword_peg(self)
  self:remove_peg(keyword_name)
end

function PEGParser:add_keywords(keywords)
  for _,keyword in ipairs(keywords) do
    internal_add_keyword(self, keyword)
  end
  recompile_keyword_peg(self)
end

function PEGParser:add_syntax_errors(syntax_errors)
  tabler.update(self.syntax_errors, syntax_errors)
end

function PEGParser:parse(srccontent, srcname, pegname)
  if not pegname then
    pegname = 'sourcecode'
  end
  local ast, syntaxlabel, errpos = self:match(pegname, srccontent, srcname)
  if not ast then
    local errmsg = self.syntax_errors[syntaxlabel] or syntaxlabel
    local src = {content=srccontent, name=srcname or 'input'}
    local message = errorer.get_pretty_source_pos_errmsg(src, errpos, nil, errmsg, 'syntax error')
    except.raise({
      label = 'ParseError',
      message = message,
      syntaxlabel = syntaxlabel
    })
  end
  return ast
end

function PEGParser:clone()
  local clone = PEGParser()
  tabler.update(clone.keywords, self.keywords)
  tabler.update(clone.syntax_errors, self.syntax_errors)
  tabler.update(clone.defs, self.defs)
  tabler.update(clone.pegdescs, self.pegdescs)
  clone:set_astbuilder(self.astbuilder)
  return clone
end

return PEGParser
