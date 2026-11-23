"""Mirrorwave's tab bar: every title as Andalite/English.

The script font keeps a copy of its letters at U+100000 + the letter, and
Mirrorwave maps only that range to it, so the translation and the English
can sit side by side.
"""
from kitty.tab_bar import draw_tab_with_powerline

OFFSET = 0x100000


def andalite(text):
    return ''.join(chr(OFFSET + ord(ch)) if ch.isascii() and ch.isalpha() else ch for ch in text)


def draw_tab(draw_data, screen, tab, before, max_title_length, index, is_last, extra_data):
    tab = tab._replace(title=f'{andalite(tab.title)}/{tab.title}')
    return draw_tab_with_powerline(draw_data, screen, tab, before, max_title_length, index, is_last, extra_data)
