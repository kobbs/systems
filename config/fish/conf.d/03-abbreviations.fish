# Smart abbreviations — expand inline, visible in shell history.
# Unlike aliases, you see the expanded command before executing.
# Abbreviations with --set-cursor place the cursor at % after expansion.

status is-interactive; or return

# -- Podman (docker muscle memory) -----------------------------------------
abbr -a dk       podman
abbr -a dkps     "podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
abbr -a dkimg    "podman images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'"
abbr -a dkrm     podman rm -f
abbr -a dkrmi    podman rmi
abbr -a dklog    podman logs -f
abbr -a dkex     --set-cursor "podman exec -it % /bin/sh"
abbr -a dkrun    --set-cursor "podman run --rm -it % "
abbr -a dkc      podman-compose

# -- Git --------------------------------------------------------------------
abbr -a g        git
abbr -a gs       git status -sb
abbr -a gl       git log --oneline -20
abbr -a gd       git diff
abbr -a gds      git diff --staged
abbr -a ga       git add
abbr -a gc       --set-cursor "git commit -m '%'"
abbr -a gca      git commit --amend --no-edit
abbr -a gco      git checkout
abbr -a gsw      git switch
abbr -a gp       git push
abbr -a gpf      git push --force-with-lease
abbr -a gpl      git pull --rebase
abbr -a grb      git rebase
abbr -a gst      git stash
abbr -a gstp     git stash pop

# -- DNF (Fedora package management) ---------------------------------------
abbr -a dnfi     sudo dnf install
abbr -a dnfr     sudo dnf remove
abbr -a dnfs     dnf search
abbr -a dnfu     sudo dnf upgrade --refresh
abbr -a dnfw     dnf provides

# -- Systemctl --------------------------------------------------------------
abbr -a sc       systemctl
abbr -a scs      systemctl status
abbr -a scr      sudo systemctl restart
abbr -a sce      sudo systemctl enable --now
abbr -a scj      --set-cursor "journalctl -u % --since today -f"

# -- Kubectl (harmless if kubectl not installed) ----------------------------
abbr -a k        kubectl
abbr -a kgp      kubectl get pods
abbr -a kgs      kubectl get svc
abbr -a kgn      kubectl get nodes
abbr -a kd       kubectl describe
abbr -a kl       kubectl logs -f
abbr -a kex      --set-cursor "kubectl exec -it % -- /bin/sh"
abbr -a kctx     kubectl config use-context
abbr -a kns      --set-cursor "kubectl config set-context --current --namespace=%"

# -- Sway / Wayland --------------------------------------------------------
abbr -a swr      swaymsg reload
abbr -a swt      swaymsg -t get_tree
abbr -a swo      swaymsg -t get_outputs

# -- Navigation / general --------------------------------------------------
abbr -a ...      "cd ../.."
abbr -a ....     "cd ../../.."
abbr -a l        ls -lah
# md is a function (functions/md.fish) — abbreviation can't handle two cursor positions
abbr -a tmp      "cd (mktemp -d)"
