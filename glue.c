#include <stdio.h>
#include <stdbool.h>

#include "libcRSID.h"

#define SIDPLAYER_SRCBUF_SAMPLES (550 * 2)

int16_t sid_buf[SIDPLAYER_SRCBUF_SAMPLES];
cRSID_C64instance *sidplayer_c64 = NULL;
cRSID_SIDheader *sidplayer_header = NULL;

bool c64init(register unsigned char* data __asm("d0"), register int dataLength __asm("d1"))
{
  // init
  sidplayer_c64 = cRSID_init(27500); // sampling rate
  if (sidplayer_c64)
  {
    sidplayer_header = cRSID_processSIDfile(sidplayer_c64, data, dataLength);
    if (sidplayer_header)
    {
      cRSID_initSIDtune(sidplayer_c64, sidplayer_header, 0 /* subtune number */);
      return true;
    }
  }
  return false;
}

int16_t* c64get()
{
  cRSID_generateSound(sidplayer_c64, (unsigned char *)&sid_buf[0], SIDPLAYER_SRCBUF_SAMPLES * sizeof(int16_t));
  return sid_buf;
}

void c64uninit()
{
  // cleanup
  cRSID_initC64(sidplayer_c64);
  sidplayer_c64 = NULL;
}