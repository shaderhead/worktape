import Darwin
import Foundation

@main
struct Worktape {
    static func main() async {
        switch Array(CommandLine.arguments.dropFirst()) {
        case ["record"]:
            exit(await record())
        case ["stop"]:
            exit(stop())
        case ["init"]:
            exit(initialise(FileManager.default.currentDirectoryPath))
        case ["hook", "zsh"]:
            print(zshHook, terminator: "")
        case ["help"], ["--help"], ["-h"]:
            print(usage)
        default:
            fputs(usage + "\n", stderr)
            exit(EX_USAGE)
        }
    }
}

let usage = """
usage: worktape <command>

  init       set up .worktapes/ in this directory
  record     record this terminal and the windows opened from it
  stop       stop the recording this shell is part of
  hook zsh   print a zsh hook that reminds you to record
"""

func stop() -> Int32 {
    guard let value = ProcessInfo.processInfo.environment["WORKTAPE_PID"],
          let pid = pid_t(value),
          name(of: pid) == "worktape"
    else {
        log("not recording")
        return 1
    }
    kill(pid, SIGTERM)
    return 0
}

func log(_ message: String) {
    fputs("worktape: \(message)\n", stderr)
}

func initialise(_ directory: String) -> Int32 {
    let project = Project(root: directory)
    let ignore = (project.recordings as NSString).appendingPathComponent(".gitignore")
    guard !FileManager.default.fileExists(atPath: ignore) else {
        log("\(project.name) is already set up")
        return 1
    }
    do {
        try FileManager.default.createDirectory(atPath: project.recordings, withIntermediateDirectories: true)
        try Data("*\n".utf8).write(to: URL(filePath: ignore))
    } catch {
        log("can't create \(project.recordings): \(error.localizedDescription)")
        return 1
    }
    log("set up .worktapes/ in \(project.name), run worktape record to start")
    return 0
}

let zshHook = #"""
_worktape_check() {
  [[ -n $WORKTAPE_RECORDING ]] && return
  local dir=$PWD
  until [[ -d $dir/.worktapes ]]; do
    [[ $dir == / ]] && { _worktape_warned=; return }
    dir=${dir:h}
  done
  [[ $dir == $_worktape_warned ]] && return
  _worktape_warned=$dir
  print -u2 -r -- $'\e[33m''○ worktape not recording'$'\e[0m'
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _worktape_check
_worktape_check

if [[ -n $WORKTAPE_RECORDING ]]; then
  _worktape_prompt() {
    if [[ -e $WORKTAPE_STATE/paused ]]; then
      psvar[8]='' psvar[9]=1
    else
      psvar[8]=1 psvar[9]=''
    fi
    local mark='%(8V.%F{red}●%f .)%(9V.%F{yellow}‖%f .)'
    [[ $PROMPT == *$mark ]] || PROMPT+=$mark
  }
  TRAPWINCH() {
    _worktape_prompt
    zle && zle reset-prompt
  }
  add-zsh-hook precmd _worktape_prompt
  [[ -d $WORKTAPE_STATE ]] && : > $WORKTAPE_STATE/prompt
fi

"""#
