{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs_22,
  gitMinimal,
  openssh,
  ripgrep,
  fd,
  uv,
  cmake,
  ninja,
  pkg-config,
  python3,
  pixman,
  cairo,
  pango,
  libpng,
  libjpeg,
  giflib,
  librsvg,
  src,
  version,
  npmDepsHash,
}:
let
  nodejs = nodejs_22;
  buildNpmPackage' = buildNpmPackage.override { inherit nodejs; };
  runtimeBins = lib.makeBinPath [
    nodejs
    gitMinimal
    openssh
    ripgrep
    fd
    uv
  ];
in
buildNpmPackage' {
  pname = "prime-agent";
  inherit src version npmDepsHash;
  npmDepsFetcherVersion = 2;

  nativeBuildInputs = [
    makeWrapper
    gitMinimal
    cmake
    ninja
    pkg-config
    python3
  ];

  buildInputs = [
    pixman
    cairo
    pango
    libpng
    libjpeg
    giflib
    librsvg
  ];

  dontUseCmakeConfigure = true;

  prePatch = ''
    cp ${../../package-lock.json} package-lock.json
  '';

  preBuild = ''
    substituteInPlace packages/ai/package.json \
      --replace-fail "npm run generate-models && " ""

    find packages -name package.json -exec sed -i \
      -e 's/--watch --preserveWatchOutput//g' \
      {} \;
  '';

  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    packageDir="$out/lib/node_modules/@earendil-works/pi-coding-agent"
    mkdir -p "$out/bin" "$packageDir" "$out/lib/node_modules/@earendil-works"

    for pkg in tui ai agent; do
      mkdir -p "$out/lib/node_modules/@earendil-works/pi-$pkg"
      cp -r "packages/$pkg/dist" "$out/lib/node_modules/@earendil-works/pi-$pkg/"
      cp "packages/$pkg/package.json" "$out/lib/node_modules/@earendil-works/pi-$pkg/"
    done

    cp -r packages/coding-agent/dist "$packageDir/"
    for path in package.json README.md CHANGELOG.md docs examples skills postinstall.cjs; do
      [ ! -e "packages/coding-agent/$path" ] || cp -r "packages/coding-agent/$path" "$packageDir/"
    done

    cp -rL node_modules/. "$out/lib/node_modules/"

    makeWrapper ${nodejs}/bin/node "$out/bin/prime-agent" \
      --add-flags "$packageDir/dist/bundle/cli.js" \
      --set PI_PACKAGE_DIR "$packageDir" \
      --set PRIME_AGENT_LAUNCHER_PATH "$out/bin/prime-agent" \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --suffix PATH : "${runtimeBins}" \
      --run 'export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/prime-agent/npm}"'

    runHook postInstall
  '';

  meta = {
    description = "Self-improving RLM agent for coding and long-running autonomous tasks";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/blob/v${version}/packages/coding-agent/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "prime-agent";
    platforms = lib.platforms.linux;
  };
}
