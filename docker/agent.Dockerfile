# Image des agents de la factory : toolchain Rust à jour, outils des gates, Node (hooks des plugins),
# Claude Code, gh, plugins/skills épinglés (factory/plugins.lock).
# Les tags `node:26` (LTS) et `rust:1` (stable) sont suivis par Dependabot (ecosystem docker).
# Debian trixie (glibc 2.41) : les binaires précompilés de cargo-mutants 27 exigent glibc >= 2.39.
FROM node:26-trixie-slim AS node

FROM rust:1-trixie

COPY --from=node /usr/local/bin/node /usr/local/bin/node

# gh 2.105.0 (2026-11-18) ; 2.106.0 du 2026-11-25 : adoptable dès le 2026-12-02.
# Le dépôt apt de GitHub ne garde que la dernière version : .deb de la release, SHA-256 lu dans
# le `digest` de l'asset et recoupé avec gh_2.105.0_checksums.txt. Vérifié le 2026-11-26.
ARG GH_VERSION=2.105.0
ARG GH_DEB_SHA256=1dac939af3e84fb3861927c984b357531341be9403b889e4aa86e8822145a09d
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git jq \
 && curl -fsSLo /tmp/gh.deb \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb" \
 && echo "${GH_DEB_SHA256}  /tmp/gh.deb" | sha256sum -c - \
 && apt-get install -y --no-install-recommends /tmp/gh.deb \
 && rm -rf /tmp/gh.deb /var/lib/apt/lists/* \
 && gh --version | grep -q "gh version ${GH_VERSION} "

# Toolchain alignée sur rust-toolchain.toml (channel = "stable")
RUN rustup toolchain install stable --profile minimal --component clippy,rustfmt,llvm-tools-preview \
 && rustup default stable

# Outils des gates, en binaires précompilés, versions épinglées (skill check-versions :
# dernière stable publiée depuis >= 7 jours). Vérifié le 2026-11-26 :
#   cargo-binstall 1.27.0 (2026-11-11)   1.28.0 du 2026-11-21 : trop récente
#   cargo-deny     0.22.0 (2026-11-19)   0.22.1 du 2026-11-24 : adoptable dès le 2026-12-01
#   cargo-llvm-cov 0.9.1  (2026-09-06)   0.9.2 du 2026-11-20 : adoptable dès le 2026-11-27
#   cargo-mutants  27.1.0 (2026-06-02)
ARG BINSTALL_VERSION=1.27.0
RUN curl -L --proto '=https' --tlsv1.2 -sSf \
      "https://raw.githubusercontent.com/cargo-bins/cargo-binstall/v${BINSTALL_VERSION}/install-from-binstall-release.sh" \
    | BINSTALL_VERSION="${BINSTALL_VERSION}" bash \
 && cargo binstall -y --locked cargo-deny@0.22.0 cargo-llvm-cov@0.9.1 cargo-mutants@27.1.0 \
 && cargo binstall -V && cargo deny --version && cargo llvm-cov --version && cargo mutants --version

# Utilisateur non-root : Claude Code refuse le mode sans permissions en root
# Les points de montage des volumes nommés (docker-compose.yml) existent dans l'image au nom de
# `factory` : Docker reprend ces droits au premier montage, sinon le volume appartient à root.
RUN useradd -m -u 1000 factory \
 && mkdir -p /usr/local/cargo/registry /workspace/target \
 && chown -R factory:factory /usr/local/cargo /usr/local/rustup /workspace
USER factory
ENV PATH="/home/factory/.local/bin:${PATH}" \
    FACTORY_AGENT=1

# Claude Code 2.1.326 = canal « stable » officiel (2026-11-16) ; « latest » 2.1.332 du 2026-11-24.
# Vérifié le 2026-11-26 (downloads.claude.ai/claude-code-releases/{stable,latest} + dates npm).
ARG CLAUDE_CODE_VERSION=2.1.326
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
 && claude --version | grep -q "^${CLAUDE_CODE_VERSION} "

# Plugins et skills, au SHA exact de factory/plugins.lock
COPY --chown=factory:factory factory/plugins.lock factory/bin/install-plugins.sh /tmp/plugins/
RUN bash /tmp/plugins/install-plugins.sh /tmp/plugins/plugins.lock

WORKDIR /workspace
COPY --chown=factory:factory docker/entrypoint.sh /usr/local/bin/factory-entrypoint
ENTRYPOINT ["factory-entrypoint"]
