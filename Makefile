CC      = gcc
CFLAGS  = -Wall -Wno-unused-function -g
TARGET  = l26c

SRCS    = symtab.c codegen.c pvm.c main.c
OBJS    = $(SRCS:.c=.o) lexer.o parser.o

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

parser.tab.c parser.tab.h: parser.y
	bison -d -Wcounterexamples -o parser.tab.c parser.y

lexer.c: lexer.l parser.tab.h
	flex -o lexer.c lexer.l

lexer.o: lexer.c
	$(CC) $(CFLAGS) -c lexer.c -o lexer.o

parser.o: parser.tab.c
	$(CC) $(CFLAGS) -c parser.tab.c -o parser.o

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o lexer.c parser.tab.c parser.tab.h $(TARGET)

test: all
	@echo "--- test1: arithmetic + control flow ---"
	./$(TARGET) tests/test1.l26
	@echo "--- test2: set operations ---"
	./$(TARGET) tests/test2.l26
	@echo "--- test3: nested scopes ---"
	./$(TARGET) tests/test3.l26
	@echo "--- test4: bonus features ---"
	./$(TARGET) tests/test4.l26
	@echo "--- test5: combined ---"
	./$(TARGET) tests/test5.l26
