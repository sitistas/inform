mkdir -p inform_greek
cd inform_greek

git clone https://github.com/ganelson/inweb.git
bash inweb/scripts/first.sh linux

git clone https://github.com/ganelson/intest.git
bash intest/scripts/first.sh
intest/Tangled/intest -help

git clone https://github.com/sitistas/inform.git inform
cd inform
bash scripts/first.sh
inblorb/Tangled/inblorb -help
../intest/Tangled/intest inform7 -show Acidity

# Test if Unicode Understanding is running properly
../intest/Tangled/intest inform7 -show UnicodeUnderstanding-G

cd ..

# Install glktermw
wget https://www.ifarchive.org/if-archive/programming/glk/implementations/glktermw-104.tar.gz
tar -xvf glktermw-104.tar.gz && rm glktermw-104.tar.gz
cd glkterm
make

cd ..

# Install glulxe (my repo)
git clone https://github.com/sitistas/glulxe.git
cd glulxe

# # Install glulxe (original repo)
# git clone https://github.com/erkyrath/glulxe.git
# cd glulxe
# sed -i '10,12 s/^/#/' Makefile
# sed -i '14,16 s/^#//' Makefile
# sed -i 's/Make.glkterm/Make.glktermw/' Makefile
# sed -i 's/-DOS_MAC/-DOS_UNIX/' Makefile

make glulxe

# Test if Inform + Glulxe is running properly
cd ../inform
bash play_game.sh helloworld.ni
