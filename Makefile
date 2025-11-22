# ============================================================================
# Awaken RSSHub Makefile
# 项目：awaken-rsshub
# 版本：1.0.0
# ============================================================================

# 项目配置
APP_NAME = awaken-rsshub
APP_VERSION = 1.0.0
DOCKER_REGISTRY = registry.cn-hangzhou.aliyuncs.com/aiawaken

# Docker Compose 文件
DEV_COMPOSE_FILE = docker/docker-compose.dev.yaml
TEST_COMPOSE_FILE = docker/docker-compose.test.yaml
PROD_COMPOSE_FILE = docker/docker-compose.yaml

# 端口配置
DEV_PORT = 1200
TEST_PORT = 11200
PROD_PORT = 21200

# 颜色定义
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
BLUE := \033[0;34m
BOLD := \033[1m
NC := \033[0m

# ============================================================================
# 帮助信息
# ============================================================================
.PHONY: help
help: ## 显示帮助信息
	@echo "$(BOLD)$(BLUE)Awaken RSSHub - 子烨的 RSS 聚合服务$(NC)"
	@echo ""
	@echo "$(BOLD)🔨 项目构建:$(NC)"
	@echo "  $(YELLOW)build$(NC)            构建项目（pnpm install）"
	@echo "  $(YELLOW)clean$(NC)            清理构建文件"
	@echo ""
	@echo "$(BOLD)💻 本地开发:$(NC)"
	@echo "  $(YELLOW)run-dev$(NC)          本地开发运行（非 Docker）"
	@echo ""
	@echo "$(BOLD)🐳 Docker 环境:$(NC)"
	@echo "  $(YELLOW)dev-start$(NC)        启动 Docker 开发环境"
	@echo "  $(YELLOW)dev-stop$(NC)         停止 Docker 开发环境"
	@echo "  $(YELLOW)dev-restart$(NC)      重启 Docker 开发环境"
	@echo "  $(YELLOW)test-start$(NC)       启动 Docker 测试环境"
	@echo "  $(YELLOW)test-stop$(NC)        停止 Docker 测试环境"
	@echo "  $(YELLOW)prod-start$(NC)       启动 Docker 生产环境"
	@echo "  $(YELLOW)prod-stop$(NC)        停止 Docker 生产环境"
	@echo ""
	@echo "$(BOLD)📊 日志管理:$(NC)"
	@echo "  $(YELLOW)logs-dev$(NC)         查看开发环境日志"
	@echo "  $(YELLOW)logs-test$(NC)        查看测试环境日志"
	@echo "  $(YELLOW)logs-prod$(NC)        查看生产环境日志"
	@echo ""
	@echo "$(BOLD)🐋 Docker 镜像:$(NC)"
	@echo "  $(YELLOW)docker-build$(NC)     构建 Docker 镜像（amd64）"
	@echo "  $(YELLOW)docker-build-multi$(NC) 构建多架构镜像并推送"
	@echo "  $(YELLOW)docker-push$(NC)      推送镜像到阿里云"
	@echo ""
	@echo "$(BOLD)🔍 环境检查:$(NC)"
	@echo "  $(YELLOW)check-env$(NC)        检查环境配置"
	@echo "  $(YELLOW)status$(NC)           查看所有环境状态"

# ============================================================================
# 基础构建命令
# ============================================================================
.PHONY: build
build: ## 安装项目依赖
	@echo "$(GREEN)🔨 安装项目依赖...$(NC)"
	pnpm install

.PHONY: clean
clean: ## 清理构建文件
	@echo "$(YELLOW)🧹 清理构建文件...$(NC)"
	rm -rf node_modules dist docker/logs/*

# ============================================================================
# 本地开发命令
# ============================================================================
.PHONY: run-dev
run-dev: ## 本地开发环境运行（非 Docker）
	@echo "$(GREEN)🚀 启动本地开发环境...$(NC)"
	pnpm run dev

# ============================================================================
# Docker 环境管理
# ============================================================================
.PHONY: dev-start
dev-start: ## 启动 Docker 开发环境
	@echo "$(GREEN)🐳 启动开发环境...$(NC)"
	docker compose -f $(DEV_COMPOSE_FILE) up -d

.PHONY: dev-stop
dev-stop: ## 停止 Docker 开发环境
	@echo "$(YELLOW)🛑 停止开发环境...$(NC)"
	docker compose -f $(DEV_COMPOSE_FILE) down

.PHONY: dev-restart
dev-restart: ## 重启 Docker 开发环境
	@echo "$(YELLOW)🔄 重启开发环境...$(NC)"
	docker compose -f $(DEV_COMPOSE_FILE) restart

.PHONY: test-start
test-start: ## 启动 Docker 测试环境
	@echo "$(GREEN)🐳 启动测试环境...$(NC)"
	docker compose -f $(TEST_COMPOSE_FILE) up -d

.PHONY: test-stop
test-stop: ## 停止 Docker 测试环境
	@echo "$(YELLOW)🛑 停止测试环境...$(NC)"
	docker compose -f $(TEST_COMPOSE_FILE) down

.PHONY: prod-start
prod-start: ## 启动 Docker 生产环境
	@echo "$(GREEN)🐳 启动生产环境...$(NC)"
	docker compose -f $(PROD_COMPOSE_FILE) up -d

.PHONY: prod-stop
prod-stop: ## 停止 Docker 生产环境
	@echo "$(YELLOW)🛑 停止生产环境...$(NC)"
	docker compose -f $(PROD_COMPOSE_FILE) down

# ============================================================================
# 日志管理
# ============================================================================
.PHONY: logs-dev
logs-dev: ## 查看开发环境日志
	@echo "$(BLUE)📋 查看开发环境日志...$(NC)"
	docker compose -f $(DEV_COMPOSE_FILE) logs -f --tail=100

.PHONY: logs-test
logs-test: ## 查看测试环境日志
	@echo "$(BLUE)📋 查看测试环境日志...$(NC)"
	docker compose -f $(TEST_COMPOSE_FILE) logs -f --tail=100

.PHONY: logs-prod
logs-prod: ## 查看生产环境日志
	@echo "$(BLUE)📋 查看生产环境日志...$(NC)"
	docker compose -f $(PROD_COMPOSE_FILE) logs -f --tail=100

# ============================================================================
# Docker 镜像管理
# ============================================================================
.PHONY: docker-build
docker-build: ## 构建 Docker 镜像（amd64）
	@if [ -z "$(version)" ]; then \
		echo "$(RED)❌ 请指定版本号！$(NC)"; \
		echo "$(YELLOW)使用方法: make docker-build version=v1.0.0$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)🔨 构建 Docker 镜像 (amd64)...$(NC)"
	docker buildx build \
		--platform linux/amd64 \
		-f docker/Dockerfile \
		-t $(APP_NAME):$(version) \
		-t $(APP_NAME):latest \
		--load \
		.
	@echo "$(GREEN)✅ 镜像构建成功！$(NC)"

.PHONY: docker-build-multi
docker-build-multi: ## 构建多架构镜像并推送
	@if [ -z "$(version)" ]; then \
		echo "$(RED)❌ 请指定版本号！$(NC)"; \
		echo "$(YELLOW)使用方法: make docker-build-multi version=v1.0.0$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)🔨 构建多架构镜像 (amd64 + arm64)...$(NC)"
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		-f docker/Dockerfile \
		-t $(DOCKER_REGISTRY)/$(APP_NAME):$(version) \
		-t $(DOCKER_REGISTRY)/$(APP_NAME):latest \
		--push \
		.
	@echo "$(GREEN)✅ 多架构镜像构建并推送成功！$(NC)"

.PHONY: docker-push
docker-push: ## 推送镜像到阿里云
	@if [ -z "$(version)" ]; then \
		echo "$(RED)❌ 请指定版本号！$(NC)"; \
		echo "$(YELLOW)使用方法: make docker-push version=v1.0.0$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)🚀 推送镜像到阿里云...$(NC)"
	docker tag $(APP_NAME):$(version) $(DOCKER_REGISTRY)/$(APP_NAME):$(version)
	docker tag $(APP_NAME):latest $(DOCKER_REGISTRY)/$(APP_NAME):latest
	docker push $(DOCKER_REGISTRY)/$(APP_NAME):$(version)
	docker push $(DOCKER_REGISTRY)/$(APP_NAME):latest
	@echo "$(GREEN)✅ 镜像推送成功！$(NC)"

# ============================================================================
# 环境检查
# ============================================================================
.PHONY: check-env
check-env: ## 检查环境配置
	@echo "$(BLUE)🔍 检查环境配置...$(NC)"
	@echo "$(BOLD)项目信息:$(NC)"
	@echo "  - 项目名称: $(APP_NAME)"
	@echo "  - 版本: $(APP_VERSION)"
	@echo "  - Node 版本: $(shell node -v 2>/dev/null || echo '未安装')"
	@echo "  - pnpm 版本: $(shell pnpm -v 2>/dev/null || echo '未安装')"
	@echo "  - Docker 版本: $(shell docker --version 2>/dev/null || echo '未安装')"

.PHONY: status
status: ## 查看所有环境状态
	@echo "$(BLUE)📊 查看环境状态...$(NC)"
	@docker ps -a --filter "name=$(APP_NAME)" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "未找到相关容器"

.DEFAULT_GOAL := help
