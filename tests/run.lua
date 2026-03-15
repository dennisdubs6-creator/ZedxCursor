package.path = package.path
  .. ';./?.lua'
  .. ';./?/init.lua'
  .. ';./tests/?.lua'

local tests = require('logic_stage4_spec')

local failed = 0
for _, case in ipairs(tests) do
  local ok, err = pcall(case.run)
  if ok then
    io.write('PASS ' .. case.name .. '\n')
  else
    failed = failed + 1
    io.write('FAIL ' .. case.name .. '\n')
    io.write('  ' .. tostring(err) .. '\n')
  end
end

if failed > 0 then
  os.exit(1)
end
