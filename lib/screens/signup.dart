import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final mobileController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String? selectedGender; // ✅ Added

  bool isLoading = false;

  Future<void> handleSignup() async {
    String name = nameController.text.trim();
    String username = usernameController.text.trim();
    String email = emailController.text.trim();
    String mobile = mobileController.text.trim();
    String password = passwordController.text;
    String confirmPassword = confirmPasswordController.text;

    // ✅ Validation
    if (name.isEmpty ||
        username.isEmpty ||
        email.isEmpty ||
        mobile.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      showMessage("Please fill all fields");
      return;
    }

    if (!email.contains("@")) {
      showMessage("Invalid email");
      return;
    }

    if (password != confirmPassword) {
      showMessage("Passwords do not match");
      return;
    }

    if (selectedGender == null) {
      showMessage("Please select gender"); // ✅ Added
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // ✅ Check username uniqueness
      QuerySnapshot usernameCheck = await FirebaseFirestore.instance
          .collection("users")
          .where("username", isEqualTo: username)
          .get();

      if (usernameCheck.docs.isNotEmpty) {
        showMessage("Username already taken");
        setState(() => isLoading = false);
        return;
      }

      // ✅ Create user in Firebase Auth
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      String uid = userCredential.user!.uid;

      // ✅ Generate unique ID
      String uniqueId = "0804${DateTime.now().millisecondsSinceEpoch}";
                                                                  
      // ✅ Save user in Firestore
      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "name": name,
        "username": username,
        "email": email,
        "mobile": mobile,
        "uid": uid,
        "uniqueId": uniqueId,
        "gender": selectedGender, // ✅ Added
        "createdAt": Timestamp.now(),
      });

      showMessage("Signup Successful!");

      if (mounted) {
        setState(() => isLoading = false);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);

      if (e.code == 'email-already-in-use') {
        showMessage("Email already in use");
      } else if (e.code == 'weak-password') {
        showMessage("Password is too weak");
      } else {
        showMessage("Signup failed: ${e.message}");
      }
    } catch (e) {
      setState(() => isLoading = false);
      showMessage("Something went wrong: $e");
    }
  }

  void showMessage(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    mobileController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.person_add, size: 70, color: Colors.green),
              const SizedBox(height: 10),
              const Text(
                "Create Account",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 25),

              TextField(
                controller: nameController,
                decoration: inputStyle("Full Name", Icons.person),
              ),
              const SizedBox(height: 15),

              TextField(
                controller: usernameController,
                decoration: inputStyle("Username", Icons.alternate_email),
              ),
              const SizedBox(height: 15),

 DropdownButtonFormField<String>(
                value: selectedGender,
                decoration:
                    inputStyle("Select Gender", Icons.person_outline),
                items: [
                  'Male',
                  'Female',
                  'Non-binary',
                  'Prefer not to say'
                ]
                    .map((gender) => DropdownMenuItem(
                          value: gender,
                          child: Text(gender),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedGender = value;
                  });
                },
              ),
              const SizedBox(height: 15),
              TextField(
                controller: emailController,
                decoration: inputStyle("Email", Icons.email),
              ),
              const SizedBox(height: 15),

              TextField(
                controller: mobileController,
                keyboardType: TextInputType.phone,
                decoration: inputStyle("Mobile", Icons.phone),
              ),
              const SizedBox(height: 15),

              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: inputStyle("Password", Icons.lock),
              ),
              const SizedBox(height: 15),

              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration:
                    inputStyle("Confirm Password", Icons.lock_outline),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : handleSignup,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Sign Up"),
                ),
              ),

              const SizedBox(height: 15),

              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  "Already have an account? Login",
                  style: TextStyle(color: Colors.green),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
