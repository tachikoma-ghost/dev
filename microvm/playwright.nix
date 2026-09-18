# A headless browser in the VM, for looking at what the manager actually
# renders rather than at what its dev server returns.
#
# Here rather than in the manager's docker image because the browser is a tool
# for inspecting the app, not a part of it: a dev image carrying browser
# libraries makes every developer pull them for something only an agent uses,
# and the libraries then live in the container's writable layer, which is
# exactly where they were lost every time the stack was recreated.
#
# The guest's /nix/store is read-only, so nothing can be fetched at runtime.
# Playwright's usual `npx playwright install` cannot work here, and that is the
# point: what the browser needs is declared, or it is absent.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    playwright-test
    playwright-driver.browsers
  ];

  environment.variables = {
    # Resolve browsers from the store instead of ~/.cache/ms-playwright, which
    # is where the unmanaged install put them and where nothing replaces them.
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";

    # The launch check looks for distro packages by apt name and cannot pass on
    # NixOS, so it refuses to start a browser whose libraries are in fact
    # present. Skipping it is the supported arrangement for this packaging.
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };
}
