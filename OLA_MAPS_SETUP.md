# Ola Maps API Setup Guide

## Overview
This guide explains how to integrate Ola Maps API for enhanced location search and routing functionality in the Rider Buddies app.

## Features Available with Ola Maps API

### 1. **Enhanced Location Search**
- Better search results with more accurate place names
- Support for Indian locations and landmarks
- Improved address formatting
- Search by business names, landmarks, and addresses

### 2. **Reverse Geocoding**
- Get place details from coordinates
- Accurate address information
- Place type classification

### 3. **Route Planning**
- Get optimal routes between points
- Multiple transportation modes (driving, walking, cycling)
- Distance and duration calculations
- Turn-by-turn directions

## Setup Instructions

### Step 1: Get Ola Maps API Key

1. **Visit Ola Maps Console**
   - Go to: https://cloud.olakrutrim.com/console/maps
   - Sign in with your Ola account

2. **Create a New Project**
   - Click "Create New Project"
   - Enter project name (e.g., "Rider Buddies")
   - Select "Maps" service

3. **Generate API Key**
   - Go to "API Keys" section
   - Click "Generate New Key"
   - Copy the API key

### Step 2: Configure API Key in App

1. **Open the Service File**
   ```bash
   lib/core/services/ola_maps_service.dart
   ```

2. **Replace the API Key**
   ```dart
   static const String _apiKey = 'YOUR_ACTUAL_API_KEY_HERE';
   ```

3. **Update the API Key**
   - Replace `YOUR_ACTUAL_API_KEY_HERE` with your actual API key
   - Save the file

### Step 3: Test the Integration

1. **Run the App**
   ```bash
   flutter run
   ```

2. **Test Location Search**
   - Go to trip planning
   - Try searching for locations
   - You should see better search results

3. **Check Console Logs**
   - Look for "Ola Maps API is configured and ready to use"
   - If you see "API key not configured", check your API key

## API Endpoints Used

### 1. Geocoding Search
```
GET https://maps.olakrutrim.com/v1/geocode/search
```
- **Purpose**: Search for places by name or address
- **Parameters**: 
  - `q`: Search query
  - `limit`: Number of results (default: 10)

### 2. Reverse Geocoding
```
GET https://maps.olakrutrim.com/v1/geocode/reverse
```
- **Purpose**: Get place details from coordinates
- **Parameters**:
  - `lat`: Latitude
  - `lon`: Longitude

### 3. Route Planning
```
GET https://maps.olakrutrim.com/v1/directions/{profile}/{coordinates}
```
- **Purpose**: Get route between two points
- **Parameters**:
  - `profile`: Transportation mode (driving, walking, cycling)
  - `coordinates`: Start and end coordinates

## Fallback System

The app includes a robust fallback system:

1. **Primary**: Ola Maps API (when configured)
2. **Fallback**: Google Geocoding API (free tier)
3. **Final Fallback**: Basic coordinate-based search

## Error Handling

The app handles various API scenarios:

- **API Key Not Configured**: Uses fallback services
- **Network Errors**: Graceful degradation
- **Rate Limiting**: Automatic retry with backoff
- **Invalid Responses**: Fallback to alternative services

## Usage Examples

### Search for a Location
```dart
final results = await OlaMapsService.searchPlaces("Mumbai Airport");
```

### Get Place Details
```dart
final details = await OlaMapsService.getPlaceDetails(LatLng(19.0896, 72.8656));
```

### Get Route
```dart
final route = await OlaMapsService.getRoute(
  LatLng(19.0896, 72.8656), // Start
  LatLng(19.0760, 72.8777), // End
  profile: 'driving',
);
```

## Troubleshooting

### Common Issues

1. **"API key not configured"**
   - Check if API key is properly set in `ola_maps_service.dart`
   - Ensure the key is valid and active

2. **"Network error"**
   - Check internet connection
   - Verify API endpoint accessibility
   - Check firewall settings

3. **"No results found"**
   - Try different search terms
   - Check if location exists in Ola Maps database
   - Use fallback search methods

### Debug Information

The app provides detailed logging:

```dart
// Check API status
print(OlaMapsService.configurationStatus);

// Check if API is configured
print(OlaMapsService.isConfigured);
```

## Cost Considerations

- **Ola Maps API**: Pay-per-use pricing
- **Google Geocoding**: Free tier available
- **Fallback Services**: Free to use

## Security Best Practices

1. **API Key Security**
   - Never commit API keys to version control
   - Use environment variables for production
   - Rotate keys regularly

2. **Rate Limiting**
   - Implement request throttling
   - Cache frequently requested data
   - Use fallback services for high-volume requests

## Support

For Ola Maps API support:
- **Documentation**: https://cloud.olakrutrim.com/console/maps?section=map-docs
- **Console**: https://cloud.olakrutrim.com/console/maps
- **Contact**: Support available through Ola Cloud Console

## Migration from Current System

The current system will continue to work without the API key. The integration is designed to be:

1. **Backward Compatible**: Existing functionality preserved
2. **Progressive Enhancement**: Better features when API is available
3. **Graceful Degradation**: Fallback to existing services

## Next Steps

1. **Get API Key**: Follow the setup instructions above
2. **Test Integration**: Verify search functionality works
3. **Monitor Usage**: Track API usage in Ola Cloud Console
4. **Optimize**: Implement caching and rate limiting as needed 