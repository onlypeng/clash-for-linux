#!/bin/sh
# clashtool_menu.sh - Menu definition and rendering module
# This file is sourced by clashtool.sh - do not execute directly
# Contains menu text definitions, menu rendering functions,
# and menu group organization that aligns with TUI module.

# === Menu Constants ===
# Menu border characters (same as TUI module)
MENU_BORDER_TOP="════════════════════════════════════════════════════════════"
MENU_BORDER_MID="├──────────────────────────────────────────────────────────────┤"
MENU_BORDER_BOT="╚══════════════════════════════════════════════════════════════╝"
MENU_LINE="║"
MENU_CONTENT_WIDTH=78
MENU_RIGHT_COL=80

# === Menu Text Definitions (English defaults) ===
# These are overwritten by i18n modules (e.g., i18n/zh_CN.sh)

# Main menu
menu_header=" Clash for Linux - Management Tool v1.2.4 "
menu_main_option0=" [0] Service Ctrl   - Start/Stop/Restart/Reload"
menu_main_option1=" [1] Auto Start    - Status & Toggle"
menu_main_option2=" [2] Gateway       - Status & Toggle"
menu_main_option3=" [3] Local Proxy   - Status & Toggle"
menu_main_option4=" [4] Sub & Config  - Manage Subscriptions & Config"
menu_main_option5=" [5] Proxy Select  - Groups/Servers/Delay/Status"
menu_main_option6=" [6] Install       - Install/Update/Uninstall Core & UI"
menu_main_option7=" [7] Tools         - Logs/Backup/Rules/Profiles/Health"
menu_main_option8=" [8] Status        - Display Clash Information"
menu_main_option9=" [9] Update        - Check/Update Script"

# Service sub-menu
menu_service_title=" Service Control "
menu_service_option1=" [1] Start Clash"
menu_service_option2=" [2] Stop Clash"
menu_service_option3=" [3] Restart Clash"
menu_service_option4=" [4] Reload Configuration"

# Install sub-menu
menu_install_title=" Install & Setup "
menu_install_option1=" [1] Install Clash Core"
menu_install_option2=" [2] Update Clash Core"
menu_install_option3=" [3] Uninstall Clash Core"
menu_install_option4=" [4] Uninstall All (including configs)"
menu_install_option5=" [5] Install/Switch yacd"
menu_install_option6=" [6] Install/Switch dashboard"
menu_install_option7=" [7] Install/Switch zashboard"
menu_install_option8=" [8] Update Current UI"
menu_install_option9=" [9] Uninstall UI"

# Proxy selection sub-menu
menu_proxy_title=" Proxy Selection "
menu_proxy_option1=" [1] Select Proxy        - Choose group & server"
menu_proxy_option2=" [2] Proxy Status        - View current selections"
menu_proxy_option3=" [3] Test Delay          - Test group/server delay"
menu_proxy_option4=" [4] URL Test            - Test connectivity"

# Subscription sub-menu
menu_subscription_title=" Subscription Management "
menu_subscription_option1=" [1] Add New Subscription"
menu_subscription_option2=" [2] Modify Subscription"
menu_subscription_option3=" [3] Delete Subscription"
menu_subscription_option4=" [4] List All Subscriptions"
menu_subscription_option5=" [5] Update Subscription"
menu_subscription_option6=" [6] Disable Auto-update"
menu_subscription_option7=" [7] Enable Auto-update"

# Config editor sub-menu
menu_config_title=" Clash Config Editor "
menu_config_option1=" [1] View All Config Items"
menu_config_option2=" [2] Set/Modify Config Item"
menu_config_option3=" [3] Delete Config Item"
menu_config_option4=" [4] View Raw Config File"
menu_config_option5=" [5] Edit Config File (GUI/nano/vim/vi)"

# Tools sub-menu
menu_tools_title=" Tools & Maintenance "
menu_tools_option1=" [1] Logs         - View/Search/Filter/Follow Logs"
menu_tools_option2=" [2] Backup      - Backup/Restore Configuration"
menu_tools_option3=" [3] Rules       - Manage Clash Rules"
menu_tools_option4=" [4] Profiles    - Multiple Configuration Profiles"
menu_tools_option5=" [5] Health      - Health Check & Auto-Recovery"

# Backup sub-menu
menu_backup_title=" Backup & Restore "
menu_backup_option1=" [1] Backup Current Configuration"
menu_backup_option2=" [2] List Backups"
menu_backup_option3=" [3] Restore from Backup"
menu_backup_option4=" [4] Delete Backup"

# Rules sub-menu
menu_rules_title=" Rules Management "
menu_rules_option1=" [1] List Available Rules"
menu_rules_option2=" [2] Enable/Disable Rules"
menu_rules_option3=" [3] Add Custom Rule"

# Profiles sub-menu
menu_profiles_title=" Profile Management "
menu_profiles_option1=" [1] List Profiles"
menu_profiles_option2=" [2] Create New Profile"
menu_profiles_option3=" [3] Switch Profile"
menu_profiles_option4=" [4] Delete Profile"

# Health sub-menu
menu_health_title=" Health Check & Recovery "
menu_health_option1=" [1] View Health Status"
menu_health_option2=" [2] Toggle Auto-Recovery"

# Logs sub-menu
menu_logs_title=" Log Viewer "
menu_logs_option1=" [1] View Recent  - Last 50 lines"
menu_logs_option2=" [2] Search       - Search by keyword"
menu_logs_option3=" [3] Filter       - Filter by log level"
menu_logs_option4=" [4] Follow       - Follow log in real-time"
menu_logs_option5=" [5] View All     - Show entire log"

# Log level filter sub-menu
menu_logs_level_title=" Log Level Filter "
menu_logs_level_debug=" [1] DEBUG"
menu_logs_level_info=" [2] INFO"
menu_logs_level_warning=" [3] WARNING"
menu_logs_level_error=" [4] ERROR"
menu_logs_level_silent=" [5] SILENT"

# Combined subscription & config sub-menu
menu_sub_config_title=" Subscriptions & Configuration "
menu_sub_config_option1=" [1] Add Subscription"
menu_sub_config_option2=" [2] Modify Subscription"
menu_sub_config_option3=" [3] Delete Subscription"
menu_sub_config_option4=" [4] List Subscriptions"
menu_sub_config_option5=" [5] Update Subscription"
menu_sub_config_option6=" [6] Disable Auto-update"
menu_sub_config_option7=" [7] Enable Auto-update"
menu_sub_config_option8=" [8] View Config Items"
menu_sub_config_option9=" [9] Set/Modify Config Item"
menu_sub_config_option10=" [a] Delete Config Item"
menu_sub_config_option11=" [b] Edit Config File (GUI/nano/vim/vi)"

# Global menu items
menu_return=" [Esc] Return to Previous Menu"
menu_exit=" [Ctrl+C] Exit"
menu_invalid_choice=" Invalid choice! Please try again."

# === Menu Rendering Functions ===

# show_menu - Non-interactive menu renderer (fallback mode)
# Arguments: title, menu items...
# Output: draws a static menu with border
show_menu() {
    printf "\033[H"
    printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_TOP}${COLOR_RESET}"
    _sm_title="$1"
    _sm_tw=$(str_display_width "$_sm_title")
    _sm_tp=$(( MENU_CONTENT_WIDTH - _sm_tw ))
    [ "$_sm_tp" -lt 0 ] && _sm_tp=0
    _sm_tpl=$(( _sm_tp / 2 ))
    printf "%b" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}${COLOR_BOLD}"
    [ "$_sm_tpl" -gt 0 ] && printf "%${_sm_tpl}s" ""
    printf "%s" "$_sm_title"
    _sm_tpr=$(( _sm_tp - _sm_tpl ))
    [ "$_sm_tpr" -gt 0 ] && printf "%${_sm_tpr}s" ""
    printf "%b\n" "${COLOR_RESET}${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}"
    printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_MID}${COLOR_RESET}"
    shift
    for item in "$@"; do
        _sm_iw=$(str_display_width "$item")
        _sm_pad=$(( MENU_CONTENT_WIDTH - _sm_iw ))
        [ "$_sm_pad" -lt 0 ] && _sm_pad=0
        printf "%b" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}${COLOR_WHITE}${item}${COLOR_RESET}"
        [ "$_sm_pad" -gt 0 ] && printf "%${_sm_pad}s" ""
        printf "%b\n" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}"
    done
    printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_BOT}${COLOR_RESET}"
    printf "\033[J"
}

# === Menu Group Definitions (aligned with TUI) ===
# Menu groups organize options by functionality, matching TUI dispatch structure

# Menu group: service (Service Control)
MENU_GROUP_SERVICE="$menu_service_title"
MENU_GROUP_SERVICE_ITEMS="
    $menu_service_option1
    $menu_service_option2
    $menu_service_option3
    $menu_service_option4
    $menu_return
"

# Menu group: install (Install & Setup)
MENU_GROUP_INSTALL="$menu_install_title"
MENU_GROUP_INSTALL_ITEMS="
    $menu_install_option1
    $menu_install_option2
    $menu_install_option3
    $menu_install_option4
    $menu_install_option5
    $menu_install_option6
    $menu_install_option7
    $menu_install_option8
    $menu_install_option9
    $menu_return
"

# Menu group: proxy (Proxy Selection)
MENU_GROUP_PROXY="$menu_proxy_title"
MENU_GROUP_PROXY_ITEMS="
    $menu_proxy_option1
    $menu_proxy_option2
    $menu_proxy_option3
    $menu_proxy_option4
    $menu_return
"

# Menu group: subscription (Subscription Management)
MENU_GROUP_SUBSCRIPTION="$menu_subscription_title"
MENU_GROUP_SUBSCRIPTION_ITEMS="
    $menu_subscription_option1
    $menu_subscription_option2
    $menu_subscription_option3
    $menu_subscription_option4
    $menu_subscription_option5
    $menu_subscription_option6
    $menu_subscription_option7
    $menu_return
"

# Menu group: config (Config Editor)
MENU_GROUP_CONFIG="$menu_config_title"
MENU_GROUP_CONFIG_ITEMS="
    $menu_config_option1
    $menu_config_option2
    $menu_config_option3
    $menu_config_option4
    $menu_config_option5
    $menu_return
"

# Menu group: tools (Tools & Maintenance)
MENU_GROUP_TOOLS="$menu_tools_title"
MENU_GROUP_TOOLS_ITEMS="
    $menu_tools_option1
    $menu_tools_option2
    $menu_tools_option3
    $menu_tools_option4
    $menu_tools_option5
    $menu_return
"

# Menu group: backup (Backup & Restore)
MENU_GROUP_BACKUP="$menu_backup_title"
MENU_GROUP_BACKUP_ITEMS="
    $menu_backup_option1
    $menu_backup_option2
    $menu_backup_option3
    $menu_backup_option4
    $menu_return
"

# Menu group: rules (Rules Management)
MENU_GROUP_RULES="$menu_rules_title"
MENU_GROUP_RULES_ITEMS="
    $menu_rules_option1
    $menu_rules_option2
    $menu_rules_option3
    $menu_return
"

# Menu group: profiles (Profile Management)
MENU_GROUP_PROFILES="$menu_profiles_title"
MENU_GROUP_PROFILES_ITEMS="
    $menu_profiles_option1
    $menu_profiles_option2
    $menu_profiles_option3
    $menu_profiles_option4
    $menu_return
"

# Menu group: health (Health Check)
MENU_GROUP_HEALTH="$menu_health_title"
MENU_GROUP_HEALTH_ITEMS="
    $menu_health_option1
    $menu_health_option2
    $menu_return
"

# Menu group: logs (Log Viewer)
MENU_GROUP_LOGS="$menu_logs_title"
MENU_GROUP_LOGS_ITEMS="
    $menu_logs_option1
    $menu_logs_option2
    $menu_logs_option3
    $menu_logs_option4
    $menu_logs_option5
    $menu_return
"

# Menu group: logs_level (Log Level Filter)
MENU_GROUP_LOGS_LEVEL="$menu_logs_level_title"
MENU_GROUP_LOGS_LEVEL_ITEMS="
    $menu_logs_level_debug
    $menu_logs_level_info
    $menu_logs_level_warning
    $menu_logs_level_error
    $menu_logs_level_silent
    $menu_return
"

# Menu group: sub_config (Combined Subscriptions & Config)
MENU_GROUP_SUB_CONFIG="$menu_sub_config_title"
MENU_GROUP_SUB_CONFIG_ITEMS="
    $menu_sub_config_option1
    $menu_sub_config_option2
    $menu_sub_config_option3
    $menu_sub_config_option4
    $menu_sub_config_option5
    $menu_sub_config_option6
    $menu_sub_config_option7
    $menu_sub_config_option8
    $menu_sub_config_option9
    $menu_sub_config_option10
    $menu_sub_config_option11
    $menu_return
"

# Main menu definition
MENU_MAIN_TITLE="$menu_header"
MENU_MAIN_ITEMS="
    $menu_main_option0
    $menu_main_option1
    $menu_main_option2
    $menu_main_option3
    $menu_main_option4
    $menu_main_option5
    $menu_main_option6
    $menu_main_option7
    $menu_main_option8
    $menu_main_option9
    $menu_exit
"

# === Menu Helper Functions ===

# get_menu_items - Return menu items for a group
# $1 = group name (service, install, proxy, etc.)
get_menu_items() {
    _gmi_group="$1"
    case "$_gmi_group" in
        service) echo "$MENU_GROUP_SERVICE_ITEMS" ;;
        install) echo "$MENU_GROUP_INSTALL_ITEMS" ;;
        proxy) echo "$MENU_GROUP_PROXY_ITEMS" ;;
        subscription) echo "$MENU_GROUP_SUBSCRIPTION_ITEMS" ;;
        config) echo "$MENU_GROUP_CONFIG_ITEMS" ;;
        tools) echo "$MENU_GROUP_TOOLS_ITEMS" ;;
        backup) echo "$MENU_GROUP_BACKUP_ITEMS" ;;
        rules) echo "$MENU_GROUP_RULES_ITEMS" ;;
        profiles) echo "$MENU_GROUP_PROFILES_ITEMS" ;;
        health) echo "$MENU_GROUP_HEALTH_ITEMS" ;;
        logs) echo "$MENU_GROUP_LOGS_ITEMS" ;;
        logs_level) echo "$MENU_GROUP_LOGS_LEVEL_ITEMS" ;;
        sub_config) echo "$MENU_GROUP_SUB_CONFIG_ITEMS" ;;
        main) echo "$MENU_MAIN_ITEMS" ;;
        *) echo "" ;;
    esac
}

# get_menu_title - Return menu title for a group
# $1 = group name (service, install, proxy, etc.)
get_menu_title() {
    _gmt_group="$1"
    case "$_gmt_group" in
        service) echo "$MENU_GROUP_SERVICE" ;;
        install) echo "$MENU_GROUP_INSTALL" ;;
        proxy) echo "$MENU_GROUP_PROXY" ;;
        subscription) echo "$MENU_GROUP_SUBSCRIPTION" ;;
        config) echo "$MENU_GROUP_CONFIG" ;;
        tools) echo "$MENU_GROUP_TOOLS" ;;
        backup) echo "$MENU_GROUP_BACKUP" ;;
        rules) echo "$MENU_GROUP_RULES" ;;
        profiles) echo "$MENU_GROUP_PROFILES" ;;
        health) echo "$MENU_GROUP_HEALTH" ;;
        logs) echo "$MENU_GROUP_LOGS" ;;
        logs_level) echo "$MENU_GROUP_LOGS_LEVEL" ;;
        sub_config) echo "$MENU_GROUP_SUB_CONFIG" ;;
        main) echo "$MENU_MAIN_TITLE" ;;
        *) echo "" ;;
    esac
}
