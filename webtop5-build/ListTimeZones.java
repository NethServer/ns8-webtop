/*
 * Copyright (C) 2025 Nethesis S.r.l.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import java.util.TimeZone;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.HashSet;
import java.util.stream.Collectors;

public class ListTimeZones {
    // Valid IANA areas as defined in the IANA Time Zone Database
    private static final Set<String> VALID_IANA_AREAS = new HashSet<>(Arrays.asList(
        "Africa",
        "America", 
        "Antarctica",
        "Arctic",
        "Asia",
        "Atlantic",
        "Australia",
        "Europe",
        "Indian",
        "Pacific",
        "Etc"  // Special area for UTC variants
    ));
    
    public static void main(String[] args) {
        // Get all timezone IDs and filter for IANA-compatible names
        List<String> ianaTimezones = Arrays.stream(TimeZone.getAvailableIDs())
            .filter(ListTimeZones::isIanaCompatible)
            .sorted()
            .collect(Collectors.toList());
        for (String timezone : ianaTimezones) {
            System.out.println(timezone);
        }
    }
    
    /**
     * Determines if a timezone ID follows IANA naming conventions.
     * Only includes timezones that start with valid IANA areas,
     * plus the special case of "UTC".
     */
    private static boolean isIanaCompatible(String timezoneId) {
        // Exclude null or empty strings
        if (timezoneId == null || timezoneId.trim().isEmpty()) {
            return false;
        }
        
        // Special case: UTC is always valid
        if (timezoneId.equals("UTC")) {
            return true;
        }
        
        // Check if timezone starts with a valid IANA area
        if (timezoneId.contains("/")) {
            String area = timezoneId.substring(0, timezoneId.indexOf("/"));
            return VALID_IANA_AREAS.contains(area);
        }
        
        // Exclude everything else (3-letter codes, GMT variants, etc.)
        return false;
    }
}
