#include <windows.h>

int PASCAL WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR CmdLine, int Show) {
   MessageBox(GetActiveWindow(), "Hello World!", "Hello Windows World", MB_OK);
   return 0;
}
