require "formula"

class Rdkit < Formula
  homepage "http://rdkit.org/"
  url "https://github.com/rdkit/rdkit/archive/Release_2015_09_2.tar.gz"
  sha256 "2ad97ec2de97729c483b89cd65470d828a4be84c88305043660cc524a86fd053"

  # devel version only needed when there is a beta release
  devel do
    url "https://github.com/rdkit/rdkit/archive/Release_2016_03_1b1.tar.gz"
    version "2016.03.1b1"
    sha256 "3c86af381ef586591368acabd0f67d90877a6944fb38c51a8c532285b31f5980"
  end

  head do
    url "https://github.com/rdkit/rdkit.git"
  end

  option 'with-java', 'Build with Java language bindings'
  option "without-inchi", "Build without InChI support"
  option "with-postgresql", "Build with PostgreSQL database cartridge"
  option "with-avalon", "Build with Avalon support"
  option "with-pycairo", "Build with py2cairo/py3cairo support"

  depends_on "cmake" => :build
  depends_on "swig" => :build if build.with? "java"
  depends_on "boost"
  depends_on :python3 => :optional
  depends_on "mcs07/cheminformatics/inchi" => :recommended
  depends_on :postgresql => :optional

  # Different dependencies if building for python3
  if build.with? "python3"
    depends_on "boost-python" => "with-python3"
    depends_on "py3cairo" if build.with? "pycairo"
  else
    depends_on :python
    depends_on "boost-python"
    depends_on "numpy" => :python
    depends_on "py2cairo" if build.with? "pycairo"
  end

  def install
    args = std_cmake_parameters.split
    args << "-DRDK_INSTALL_INTREE=OFF"
    args << "-DRDK_BUILD_SWIG_WRAPPERS=ON"  if build.with? "java"
    args << "-DRDK_BUILD_AVALON_SUPPORT=ON"  if build.with? "avalon"
    args << "-DRDK_BUILD_PGSQL=ON"  if build.head? and build.with? "postgresql"

    # Optionally build InChI support
    if build.with? "inchi"
      args << "-DRDK_BUILD_INCHI_SUPPORT=ON"
      args << "-DINCHI_INCLUDE_DIR='#{HOMEBREW_PREFIX}/include/inchi/'"
      args << "-DINCHI_LIBRARIES='#{HOMEBREW_PREFIX}/lib/libinchi.dylib'"
    end

    # Will no longer need to do all this in 2016_03_1
    if not build.head?
      if build.with? "java"
        if not File.exists? "External/java_lib/junit.jar"
          mkdir "External/java_lib"
          system "curl http://search.maven.org/remotecontent?filepath=junit/junit/4.11/junit-4.11.jar -o External/java_lib/junit.jar"
        end
      end
      if build.with? "avalon"
        system "curl -L https://downloads.sourceforge.net/project/avalontoolkit/AvalonToolkit_1.2/AvalonToolkit_1.2.0.source.tar -o External/AvalonTools/avalon.tar"
        system "tar xf External/AvalonTools/avalon.tar -C External/AvalonTools"
        args << "-DAVALONTOOLS_DIR='#{buildpath}/External/AvalonTools/SourceDistribution'"
      end
    end

    # Get Python location
    pyexec = if build.with? "python3" then `which python3`.strip else `which python`.strip end
    pypref = %x(#{pyexec} -c 'import sys;print(sys.prefix)').chomp
    pyinc = %x(#{pyexec} -c 'from distutils import sysconfig;print(sysconfig.get_python_inc(True))').chomp
    pyvers = "python" + %x(#{pyexec} -c 'import sys;print(sys.version[:3])').chomp
    args << "-DPYTHON_EXECUTABLE='#{pyexec}'"
    args << "-DPYTHON_INCLUDE_DIR='#{pyinc}'"
    if File.exist? "#{pypref}/Python"
      args << "-DPYTHON_LIBRARY='#{pypref}/Python'"
    elsif File.exists? "#{pypref}/lib/lib#{pyvers}.a"
      args << "-DPYTHON_LIBRARY='#{pypref}/lib/lib#{pyvers}.a'"
    else
      args << "-DPYTHON_LIBRARY='#{pypref}/lib/lib#{pyvers}.dylib'"
    end

    # Get numpy location
    npp = %x(#{pyexec} -c 'import numpy;print(numpy.get_include())').chomp
    args << "-DPYTHON_NUMPY_INCLUDE_PATH='#{npp}'"

    # Run cmake, make, make install
    args << "."
    system "cmake", *args
    system "make"
    system "make install"

    # Remove unneeded cmake files
    rm_f Dir["#{lib}/*.cmake"]

    # Install java files
    if build.with? "java"
      libexec.install "Code/JavaWrappers/gmwrapper/org.RDKit.jar"
      libexec.install "Code/JavaWrappers/gmwrapper/org.RDKitDoc.jar"
      lib.install "Code/JavaWrappers/gmwrapper/libGraphMolWrap.jnilib"
    end

    # Optionally build PostgreSQL cartridge
    if build.with? "postgresql"
      if build.head?
        mv "Code/PgSQL/rdkit/rdkit.sql91.in", "Code/PgSQL/rdkit/rdkit--3.4.sql"
        (share + 'postgresql/extension').install "Code/PgSQL/rdkit/rdkit--3.4.sql"
        (share + 'postgresql/extension').install "Code/PgSQL/rdkit/rdkit.control"
        (lib + 'postgresql').install "Code/PgSQL/rdkit/rdkit.so"
      else
        args = ["RDBASE=#{prefix}", "USE_THREADS=1", "CFLAGS='-I#{include}/rdkit'", "THREADLIBS=-L#{HOMEBREW_PREFIX}/lib -lboost_thread-mt -lboost_system"]
        cd "Code/PgSQL/rdkit" do
          system "make", *args
          system "make install"
        end
      end
    end
  end

  def caveats
    if build.with? "java" then <<-EOS.undent
      The RDKit Jar file has been installed to:
        #{libexec}/org.RDKit.jar
      You may need to link the Java bindings into the Java Extensions folder:
        sudo mkdir -p /Library/Java/Extensions
        sudo ln -s #{lib}/libGraphMolWrap.jnilib /Library/Java/Extensions/libGraphMolWrap.jnilib
      EOS
    end
  end

  test do
    (testpath/"rdtest.cpp").write <<-EOS.undent
      #include <GraphMol/RDKitBase.h>
      #include <GraphMol/SmilesParse/SmilesParse.h>
      using namespace RDKit;
      int main(int argc, char *argv[]) {
          RWMol *mol = SmilesToMol("C=CC=CC=C", false);
          mol->debugMol(std::cout);
      }
    EOS
    system ENV.cxx, "-I#{HOMEBREW_PREFIX}/include/rdkit", "-L#{HOMEBREW_PREFIX}/lib", "-lSmilesParse", "-lGraphMol", "-lRDGeometryLib", "-lRDGeneral", "-o", "rdtest", "rdtest.cpp"
    system "./rdtest"
  end
end
