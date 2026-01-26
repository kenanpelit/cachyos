local chassis = dcli.hardware.chassis_type()
local package_files = { "packages-core.yaml" }

if chassis ~= "server" then
  table.insert(package_files, "packages-desktop.yaml")
end

return {
  description = "Base packages (portable config)",
  package_files = package_files,
}
