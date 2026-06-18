CC      = gcc
CFLAGS  = -Wall -Wno-unused-function -g
TARGET  = l26c
TEST_DIR = ../测试

SRCS    = symtab.c codegen.c pvm.c main.c
OBJS    = $(SRCS:.c=.o) lexer.o parser.o

.PHONY: all clean test test-errors test-all

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
	printf "5\n" | ./$(TARGET) "$(TEST_DIR)/正向测试/test1.l26"
	@echo "--- test2: set operations ---"
	./$(TARGET) "$(TEST_DIR)/正向测试/test2.l26"
	@echo "--- test3: nested scopes ---"
	./$(TARGET) "$(TEST_DIR)/正向测试/test3.l26"
	@echo "--- test4: bonus features ---"
	./$(TARGET) "$(TEST_DIR)/正向测试/test4.l26"
	@echo "--- test5: combined ---"
	./$(TARGET) "$(TEST_DIR)/正向测试/test5.l26"

test-errors: all
	TEST_DIR="$(TEST_DIR)/负向测试" ./scripts/run_error_tests.sh

test-all: test test-errors
