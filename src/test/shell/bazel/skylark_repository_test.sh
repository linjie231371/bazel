#!/bin/bash
#
# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Test the local_repository binding
#

# Load test environment
source $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-setup.sh \
  || { echo "test-setup.sh not found!" >&2; exit 1; }

# Basic test.
function test_macro_local_repository() {
  create_new_workspace
  repo2=$new_workspace_dir

  mkdir -p carnivore
  cat > carnivore/BUILD <<'EOF'
genrule(
    name = "mongoose",
    cmd = "echo 'Tra-la!' | tee $@",
    outs = ["moogoose.txt"],
    visibility = ["//visibility:public"],
)
EOF

  cd ${WORKSPACE_DIR}
  cat > WORKSPACE <<EOF
load('/test', 'macro')

macro('$repo2')
EOF

  # Empty package for the .bzl file
  echo -n >BUILD

  # Our macro
  cat >test.bzl <<EOF
def macro(path):
  print('bleh')
  native.local_repository(name='endangered', path=path)
  native.bind(name='mongoose', actual='@endangered//carnivore:mongoose')
EOF
  mkdir -p zoo
  cat > zoo/BUILD <<'EOF'
genrule(
    name = "ball-pit1",
    srcs = ["@endangered//carnivore:mongoose"],
    outs = ["ball-pit1.txt"],
    cmd = "cat $< >$@",
)

genrule(
    name = "ball-pit2",
    srcs = ["//external:mongoose"],
    outs = ["ball-pit2.txt"],
    cmd = "cat $< >$@",
)
EOF

  bazel build //zoo:ball-pit1 >& $TEST_log || fail "Failed to build"
  expect_log "bleh."
  expect_log "Tra-la!"  # Invalidation
  cat bazel-genfiles/zoo/ball-pit1.txt >$TEST_log
  expect_log "Tra-la!"

  bazel build //zoo:ball-pit1 >& $TEST_log || fail "Failed to build"
  expect_not_log "Tra-la!"  # No invalidation

  bazel build //zoo:ball-pit2 >& $TEST_log || fail "Failed to build"
  expect_not_log "Tra-la!"  # No invalidation
  cat bazel-genfiles/zoo/ball-pit2.txt >$TEST_log
  expect_log "Tra-la!"

  # Test invalidation of the WORKSPACE file
  create_new_workspace
  repo2=$new_workspace_dir

  mkdir -p carnivore
  cat > carnivore/BUILD <<'EOF'
genrule(
    name = "mongoose",
    cmd = "echo 'Tra-la-la!' | tee $@",
    outs = ["moogoose.txt"],
    visibility = ["//visibility:public"],
)
EOF
  cd ${WORKSPACE_DIR}
  cat >test.bzl <<EOF
def macro(path):
  print('blah')
  native.local_repository(name='endangered', path='$repo2')
  native.bind(name='mongoose', actual='@endangered//carnivore:mongoose')
EOF
  bazel build //zoo:ball-pit1 >& $TEST_log || fail "Failed to build"
  expect_log "blah."
  expect_log "Tra-la-la!"  # Invalidation
  cat bazel-genfiles/zoo/ball-pit1.txt >$TEST_log
  expect_log "Tra-la-la!"

  bazel build //zoo:ball-pit1 >& $TEST_log || fail "Failed to build"
  expect_not_log "Tra-la-la!"  # No invalidation

  bazel build //zoo:ball-pit2 >& $TEST_log || fail "Failed to build"
  expect_not_log "Tra-la-la!"  # No invalidation
  cat bazel-genfiles/zoo/ball-pit2.txt >$TEST_log
  expect_log "Tra-la-la!"
}

function test_load_from_symlink_to_outside_of_workspace() {
  OTHER=$TEST_TMPDIR/other

  cat > WORKSPACE<<EOF
load("/a/b/c", "c")
EOF

  mkdir -p $OTHER/a/b
  touch $OTHER/a/b/BUILD
  cat > $OTHER/a/b/c.bzl <<EOF
def c():
  pass
EOF

  touch BUILD
  ln -s $TEST_TMPDIR/other/a a
  bazel build //:BUILD || fail "Failed to build"
  rm -fr $TEST_TMPDIR/other
}

# Test load from repository.
function test_external_load_from_workspace() {
  create_new_workspace
  repo2=$new_workspace_dir

  mkdir -p carnivore
  cat > carnivore/BUILD <<'EOF'
genrule(
    name = "mongoose",
    cmd = "echo 'Tra-la-la!' | tee $@",
    outs = ["moogoose.txt"],
    visibility = ["//visibility:public"],
)
EOF

  create_new_workspace
  repo3=$new_workspace_dir
  # Our macro
  cat >WORKSPACE
  cat >test.bzl <<EOF
def macro(path):
  print('bleh')
  native.local_repository(name='endangered', path=path)
EOF
  cat >BUILD <<'EOF'
exports_files(["test.bzl"])
EOF

  cd ${WORKSPACE_DIR}
  cat > WORKSPACE <<EOF
local_repository(name='proxy', path='$repo3')
load('@proxy//:test.bzl', 'macro')
macro('$repo2')
EOF

  bazel build @endangered//carnivore:mongoose >& $TEST_log \
    || fail "Failed to build"
  expect_log "bleh."
}

# Test loading a repository with a load statement in the WORKSPACE file
function test_load_repository_with_load() {
  create_new_workspace
  repo2=$new_workspace_dir

  echo "Tra-la!" > data.txt
  cat <<'EOF' >BUILD
exports_files(["data.txt"])
EOF

  cat <<'EOF' >ext.bzl
def macro():
  print('bleh')
EOF

  cat <<'EOF' >WORKSPACE
workspace(name = "foo")
load("//:ext.bzl", "macro")
macro()
EOF

  cd ${WORKSPACE_DIR}
  cat > WORKSPACE <<EOF
local_repository(name='foo', path='$repo2')
load("@foo//:ext.bzl", "macro")
macro()
EOF

  cat > BUILD <<'EOF'
genrule(name = "foo", srcs=["@foo//:data.txt"], outs=["foo.txt"], cmd = "cat $< | tee $@")
EOF

  bazel build //:foo >& $TEST_log || fail "Failed to build"
  expect_log "bleh"
  expect_log "Tra-la!"
}

function test_skylark_local_repository() {
  create_new_workspace
  repo2=$new_workspace_dir

  cat > BUILD <<'EOF'
genrule(name='bar', cmd='echo foo | tee $@', outs=['bar.txt'])
EOF

  cd ${WORKSPACE_DIR}
  cat > WORKSPACE <<EOF
load('/test', 'repo')
repo(name='foo', path='$repo2')
EOF

  # Our custom repository rule
  cat >test.bzl <<EOF
def _impl(ctx):
  ctx.symlink(ctx.path(ctx.attr.path), ctx.path(""))

repo = repository_rule(
    implementation=_impl,
    local=True,
    attrs={"path": attr.string(mandatory=True)})
EOF
  # Need to be in a package
  cat > BUILD

  bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_log "foo"
  cat bazel-genfiles/external/foo/bar.txt >$TEST_log
  expect_log "foo"
}

function setup_skylark_repository() {
  create_new_workspace
  repo2=$new_workspace_dir

  cat > bar.txt
  echo "filegroup(name='bar', srcs=['bar.txt'])" > BUILD

  cd "${WORKSPACE_DIR}"
  cat > WORKSPACE <<EOF
load('/test', 'repo')
repo(name = 'foo')
EOF
  # Need to be in a package
  cat > BUILD
}

function test_skylark_repository_which_and_execute() {
  setup_skylark_repository

  bazel info

  # Test we are using the client environment, not the server one
  echo "#!/bin/bash" > bin.sh
  echo "exit 0" >> bin.sh
  chmod +x bin.sh

  # Our custom repository rule
  cat >test.bzl <<EOF
def _impl(ctx):
  bash = ctx.which("bash")
  if bash == None:
    fail("Bash not found!")
  bin = ctx.which("bin.sh")
  if bin == None:
    fail("bin.sh not found!")
  result = ctx.execute([bash, "--version"])
  if result.return_code != 0:
    fail("Non-zero return code from bash: " + result.return_code)
  if result.stderr != "":
    fail("Non-empty error output: " + result.stderr)
  print(result.stdout)
  # Symlink so a repository is created
  ctx.symlink(ctx.path("$repo2"), ctx.path(""))
repo = repository_rule(implementation=_impl, local=True)
EOF

  PATH="${PATH}:${PWD}" bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_log "version"
}

function test_skylark_repository_execute_stderr() {
  setup_skylark_repository

  cat >test.bzl <<EOF
def _impl(ctx):
  result = ctx.execute([str(ctx.which("bash")), "-c", "echo erf >&2; exit 1"])
  if result.return_code != 1:
    fail("Incorrect return code from bash (should be 1): " + result.return_code)
  if result.stdout != "":
    fail("Non-empty output: %s (stderr was %s)" % (result.stdout, result.stderr))
  print(result.stderr)
  # Symlink so a repository is created
  ctx.symlink(ctx.path("$repo2"), ctx.path(""))
repo = repository_rule(implementation=_impl, local=True)
EOF

  bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_log "erf"
}

function test_skylark_repository_environ() {
  setup_skylark_repository

  # Our custom repository rule
  cat >test.bzl <<EOF
def _impl(ctx):
  print(ctx.os.environ["FOO"])
  # Symlink so a repository is created
  ctx.symlink(ctx.path("$repo2"), ctx.path(""))
repo = repository_rule(implementation=_impl, local=False)
EOF

  # TODO(dmarting): We should seriously have something better to force a refetch...
  bazel clean --expunge
  FOO=BAR bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_log "BAR"

  FOO=BAR bazel clean --expunge >& $TEST_log
  FOO=BAR bazel info >& $TEST_log

  FOO=BAZ bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_log "BAZ"

  # Test that we don't re-run on server restart.
  FOO=BEZ bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_not_log "BEZ"
  bazel shutdown >& $TEST_log
  FOO=BEZ bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_not_log "BEZ"

  # Test modifying test.bzl invalidate the repository
  cat >test.bzl <<EOF
def _impl(ctx):
  print(ctx.os.environ["BAR"])
  # Symlink so a repository is created
  ctx.symlink(ctx.path("$repo2"), ctx.path(""))
repo = repository_rule(implementation=_impl, local=True)
EOF
  BAR=BEZ bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_log "BEZ"

  # Shutdown and modify again
  bazel shutdown
  cat >test.bzl <<EOF
def _impl(ctx):
  print(ctx.os.environ["BAZ"])
  # Symlink so a repository is created
  ctx.symlink(ctx.path("$repo2"), ctx.path(""))
repo = repository_rule(implementation=_impl, local=True)
EOF
  BAZ=BOZ bazel build @foo//:bar >& $TEST_log || fail "Failed to build"
  expect_log "BOZ"
}

function test_skylark_repository_executable_flag() {
  setup_skylark_repository

  # Our custom repository rule
  cat >test.bzl <<EOF
def _impl(ctx):
  ctx.file("test.sh", "exit 0")
  ctx.file("BUILD", "sh_binary(name='bar',srcs=['test.sh'])", False)
  ctx.template("test2", Label("//:bar"), {}, False)
  ctx.template("test2.sh", Label("//:bar"), {}, True)
repo = repository_rule(implementation=_impl, local=True)
EOF
  cat >bar

  bazel run @foo//:bar >& $TEST_log || fail "Execution of @foo//:bar failed"
  output_base=$(bazel info output_base)
  test -x "${output_base}/external/foo/test.sh" || fail "test.sh is not executable"
  test -x "${output_base}/external/foo/test2.sh" || fail "test2.sh is not executable"
  test ! -x "${output_base}/external/foo/BUILD" || fail "BUILD is executable"
  test ! -x "${output_base}/external/foo/test2" || fail "test2 is executable"
}

function tear_down() {
  true
}

run_suite "local repository tests"
