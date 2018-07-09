# Copyright 2018 Daniel Azuma
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the copyright holder, nor the names of any other
#   contributors to this software, may be used to endorse or promote products
#   derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
;

unless ::ENV["TOYS_CORE_LIB_PATH"] == ::File.absolute_path(::File.join(__dir__, "lib"))
  puts "NOTE: Rerunning toys binary from the local repo\n\n"
  ::Kernel.exec(::File.join(__dir__, "toys-dev"), *::ARGV)
end

expand :clean, paths: ["pkg", "doc", ".yardoc", "tmp"]

expand :minitest, libs: ["lib", "test"]

expand :rubocop

expand :yardoc do |t|
  t.generate_output_flag = true
  t.fail_on_warning = true
  t.fail_on_undocumented_objects = true
end

expand :rdoc, output_dir: "doc"

expand :gem_build

expand :gem_build, name: "release", push_gem: true

tool "ci" do
  desc "Run all CI checks"

  long_desc "The CI tool runs all CI checks for the toys-core gem, including" \
              " unit tests, rubocop, and documentation checks. It is useful" \
              " for running tests in normal development, as well as being" \
              " the entrypoint for CI systems like Travis. Any failure will" \
              " result in a nonzero result code."

  include :exec
  include :terminal

  def run_stage(name, tool)
    if exec_tool(tool).success?
      puts("** #{name} passed\n\n", :green, :bold)
    else
      puts("** CI terminated: #{name} failed!", :red, :bold)
      exit(1)
    end
  end

  def run
    run_stage("Tests", ["test"])
    run_stage("Style checker", ["rubocop"])
    run_stage("Docs generation", ["yardoc", "--no-output"])
  end
end
