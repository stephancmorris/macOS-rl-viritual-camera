#include <iostream>
#include "CinematicCoreMacOS/CinematicCoreMacOS/include/DeckLinkAPI.h"

int main() {
    IDeckLinkIterator* iterator = CreateDeckLinkIteratorInstance();
    if (!iterator) {
        std::cout << "Failed to create iterator." << std::endl;
        return 1;
    }
    IDeckLink* deckLink = nullptr;
    int count = 0;
    while (iterator->Next(&deckLink) == S_OK) {
        count++;
        deckLink->Release();
    }
    iterator->Release();
    std::cout << "Found " << count << " devices." << std::endl;
    return 0;
}
