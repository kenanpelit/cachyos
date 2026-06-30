local chassis = mdots.hardware.chassis_type()
local package_files = { "packages-core.yaml" }
local post_install_hook = nil

if chassis ~= "server" then
  table.insert(package_files, "packages-desktop.yaml")
  post_install_hook = "scripts/ensure-extra-tigervnc.sh"
end

return {
  description = "Base packages (portable config)",
  package_files = package_files,
  post_install_hook = post_install_hook,
  post_hook_behavior = "always",
}
