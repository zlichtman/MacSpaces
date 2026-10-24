#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/Calculator.swift Tests/CalculatorChecks.swift -o "$check_dir/check-calculator"
"$check_dir/check-calculator"
