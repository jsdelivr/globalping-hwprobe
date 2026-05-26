#!/bin/bash
# led-control.sh - LED control functions for eMMC programmer
#
# Can be used two ways:
# 1. Sourced as library:  source /usr/bin/led-control.sh; emmc_led_flashing
# 2. Called directly:     /usr/bin/led-control.sh flashing &
#
# LED Patterns for eMMC Programmer:
#   emmc_led_error    / error    - Solid RED (not started / failed early)
#   emmc_led_flashing / flashing - Fast blinking GREEN (flashing in progress)
#   emmc_led_failed   / failed   - Slow blinking RED (flashing failed)
#   emmc_led_success  / success  - Both RED and GREEN solid (flashing succeeded)

LED_RED="/sys/class/leds/sys_led"
LED_GREEN="/sys/class/leds/user_led"

# Turn off both LEDs
emmc_led_off() {
    echo "none" > ${LED_RED}/trigger 2>/dev/null
    echo 0 > ${LED_RED}/brightness 2>/dev/null
    echo "none" > ${LED_GREEN}/trigger 2>/dev/null
    echo 0 > ${LED_GREEN}/brightness 2>/dev/null
}

# Error: Solid RED (not started or failed early)
emmc_led_error() {
    emmc_led_off
    echo 1 > ${LED_RED}/brightness
}

# Flashing: Fast blinking GREEN (100ms on/100ms off)
emmc_led_flashing() {
    emmc_led_off
    while true; do
        echo 1 > ${LED_GREEN}/brightness
        sleep 0.1
        echo 0 > ${LED_GREEN}/brightness
        sleep 0.1
    done
}

# Failed: Slow blinking RED (1s on/1s off)
emmc_led_failed() {
    emmc_led_off
    while true; do
        echo 1 > ${LED_RED}/brightness
        sleep 1
        echo 0 > ${LED_RED}/brightness
        sleep 1
    done
}

# Success: Both RED and GREEN solid
emmc_led_success() {
    emmc_led_off
    echo 1 > ${LED_RED}/brightness
    echo 1 > ${LED_GREEN}/brightness
}

# If called directly (not sourced), run the requested pattern
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Turn off both LEDs initially
    emmc_led_off

    case "$1" in
        error)
            emmc_led_error
            # Keep LED on forever
            while true; do sleep 3600; done
            ;;
        flashing)
            emmc_led_flashing
            ;;
        failed)
            emmc_led_failed
            ;;
        success)
            emmc_led_success
            # Keep LEDs on forever
            while true; do sleep 3600; done
            ;;
        *)
            echo "Usage: $0 {error|flashing|failed|success}"
            echo ""
            echo "LED Patterns:"
            echo "  error    - Solid RED (not started / failed early)"
            echo "  flashing - Fast blinking GREEN (flashing in progress)"
            echo "  failed   - Slow blinking RED (flashing failed)"
            echo "  success  - Both RED and GREEN solid (flashing succeeded)"
            exit 1
            ;;
    esac
fi
