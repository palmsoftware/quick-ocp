.PHONY: lint fix-lint help

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Check shell script formatting
	@echo "Linting shell scripts in scripts/ directory..."
	@shfmt -d -i 2 -ci scripts/*.sh
	@if [ $$? -eq 0 ]; then \
		echo "✅ All shell scripts are properly formatted!"; \
	else \
		echo "❌ Shell script formatting issues found!"; \
		echo "Run 'make fix-lint' to fix them."; \
		exit 1; \
	fi

fix-lint: ## Fix shell script formatting issues
	@echo "Fixing shell script formatting in scripts/ directory..."
	@shfmt -w -i 2 -ci scripts/*.sh
	@echo "✅ All shell scripts have been formatted!"

