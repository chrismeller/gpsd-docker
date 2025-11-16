# Docker Compose GPS NTP Server for Raspberry Pi

This setup runs GPSD and Chrony in separate Docker containers on a Raspberry Pi, creating a GPS-disciplined NTP server.

## Prerequisites

- Raspberry Pi with 64-bit OS (Debian or Ubuntu)
- Docker and Docker Compose installed
- USB GPS adapter connected to the Raspberry Pi
- System time initially set reasonably close to actual time (within a few hours)

## USB Device Setup

Before running the containers, identify your GPS device:

```bash
# List USB devices
lsusb

# Find the device path (usually /dev/ttyUSB0 or /dev/ttyACM0)
ls -la /dev/tty*

# Check if it's readable
cat /dev/ttyUSB0  # Should show NMEA strings
# Press Ctrl+C to stop
```

If your device is NOT at `/dev/ttyUSB0`, edit `docker-compose.yml` and change the `devices` section under `gpsd` service.

## File Structure

```
.
├── docker-compose.yml      # Main compose file
├── Dockerfile.gpsd         # GPSD service image
├── Dockerfile.chrony       # Chrony service image
└── chrony.conf             # Chrony configuration
```

## Building and Running

### First Time Setup

```bash
# Build both images (multi-arch for ARM64)
docker-compose build

# Start the services
docker-compose up -d

# Check status
docker-compose logs -f
```

### Verify Services Are Running

```bash
# Check GPSD is reading GPS data
docker-compose exec gpsd gpspipe -r -n 5

# Check Chrony is synchronized
docker-compose exec chrony chronyc tracking

# Expected output includes reference clock "GPS" and stratum 1
```

### Query the NTP Server from Another Machine

```bash
# From another computer on your network (replace IP with your Pi's IP)
ntpdate -q 192.168.1.100  # Query
ntpdate 192.168.1.100      # Set time (requires sudo)

# Or using chronyc
chronyc -h 192.168.1.100 tracking
```

## Configuration Adjustments

### Network Access

Edit `chrony.conf` to allow different networks:

```conf
allow 192.168.1.0/24    # Your network range
allow 10.0.0.0/8        # Docker networks
```

### GPS Device Path

If your device is at a different path, edit `docker-compose.yml`:

```yaml
devices:
  - /dev/ttyACM0:/dev/ttyUSB0  # If device is /dev/ttyACM0
```

### Chrony Polling Intervals

In `chrony.conf`, adjust for faster sync or lower CPU usage:

```conf
minpoll 5   # Faster (32 second intervals) - more CPU
minpoll 8   # Slower (256 second intervals) - less CPU
```

## Troubleshooting

### GPSD not connecting to GPS device

```bash
# Check device permissions
ls -la /dev/ttyUSB0

# Add user to dialout group (if needed outside Docker)
sudo usermod -a -G dialout $USER

# Check for NMEA data
docker-compose exec gpsd gpspipe -r -n 1
```

### Chrony not synchronizing

```bash
# Check if GPSD is providing data
docker-compose exec chrony chronyc sources

# Should show "SHM0" as GPS source

# If not locked, wait 5+ minutes for GPS fix
docker-compose exec chrony chronyc tracking
```

### Containers won't start

```bash
# Check full logs
docker-compose logs

# Rebuild images
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Permission issues with time adjustment

```bash
# Chrony needs SYS_TIME capability - it's already included in docker-compose.yml
# If still having issues, verify the cap_add section is present
docker-compose exec chrony capsh --print | grep cap_sys_time
```

## Stopping Services

```bash
# Stop containers
docker-compose stop

# Stop and remove containers
docker-compose down

# Remove everything including images
docker-compose down --rmi all
```

## Performance Notes

- Initial GPS synchronization takes 5-15 minutes depending on GPS fix quality
- Chrony reaches stratum 1 once GPS provides continuous fixes
- After synchronization, time accuracy is typically within 100ms or better
- The setup uses minimal CPU (~5-10% on a Pi 4) once synchronized

## Network Time Protocol Query Tools

### On Linux
```bash
ntpdate -q <ntp-server-ip>
ntpstat
chronyc -h <ntp-server-ip> tracking
```

### On macOS
```bash
sntp -S <ntp-server-ip>
```

### On Windows
```cmd
w32tm /query /peer
w32tm /config /manualpeerlist:"<ntp-server-ip>" /syncfromflags:manual /update
```

## Security Notes

- This setup opens port 123 UDP to any IP in the allowed ranges
- For production, restrict `allow` directives in `chrony.conf` to specific subnets
- Consider using firewall rules to limit NTP access
- Monitor GPS quality with `gpspipe` - poor signal means poor time accuracy

## Further Reading

- GPSD documentation: https://gpsd.gitlab.io/gpsd/
- Chrony documentation: https://chrony.tuxfamily.org/
- NTP best practices: https://www.ntp.org/
